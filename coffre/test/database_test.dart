import 'dart:io';

import 'package:coffre/data/database.dart';
import 'package:coffre/data/db_opener.dart';
import 'package:coffre/data/enums.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('création, filtres Inbox / Tâches / Fait', () async {
    final task = await db.createItem(
      kind: ItemKind.task,
      content: 'Appeler le médecin',
      tags: ['santé'],
    );
    await db.createItem(kind: ItemKind.idea, content: 'Nouvelle idée');

    expect(
      (await db.watchList(InboxFilter.inbox, SortMode.recent).first).length,
      2,
    );
    expect(
      (await db.watchList(InboxFilter.tasks, SortMode.recent).first).single.id,
      task.id,
    );

    await db.setStatus(task.id, ItemStatus.done);
    final done = await db.watchList(InboxFilter.done, SortMode.recent).first;
    expect(done.single.doneAt, isNotNull);
    expect(
      (await db.watchList(InboxFilter.inbox, SortMode.recent).first).length,
      1,
    );

    final counts = await db.watchCounts().first;
    expect(counts[InboxFilter.done], 1);
    expect(counts[InboxFilter.ideas], 1);
  });

  test('recherche sans accents ni majuscules, tags inclus', () async {
    await db.createItem(
      kind: ItemKind.note,
      content: 'Réunion équipe SAFA',
      tags: ['cpas'],
    );
    await db.createItem(kind: ItemKind.note, content: 'Autre chose');
    expect((await db.watchSearch('reunion').first).length, 1);
    expect((await db.watchSearch('EQUIPE safa').first).length, 1);
    expect((await db.watchSearch('cpas').first).length, 1);
    expect((await db.watchSearch('100%').first).length, 0);
  });

  test('snooze reporte le rappel, tri par date de rappel', () async {
    final a = await db.createItem(kind: ItemKind.task, content: 'A');
    final b = await db.createItem(
      kind: ItemKind.task,
      content: 'B',
      remindAt: DateTime.now().add(const Duration(hours: 2)),
    );
    final snoozed = await db.snooze(a.id, const Duration(minutes: 15));
    expect(snoozed!.remindAt!.isAfter(DateTime.now()), isTrue);
    final ordered = await db
        .watchList(InboxFilter.reminders, SortMode.reminder)
        .first;
    expect(ordered.map((i) => i.id), [a.id, b.id]);
    expect((await db.pendingReminders()).length, 2);
  });

  test('import ignore les doublons', () async {
    final existing = await db.createItem(
      kind: ItemKind.idea,
      content: 'Doublon',
    );
    final added = await db.importItems([
      ItemsCompanion.insert(
        kind: ItemKind.idea,
        content: 'Doublon',
        createdAt: existing.createdAt,
        updatedAt: existing.updatedAt,
      ),
      ItemsCompanion.insert(
        kind: ItemKind.task,
        content: 'Nouveau',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
        priority: const Value(ItemPriority.high),
      ),
    ]);
    expect(added.single.content, 'Nouveau');
  });

  test(
    'migration v1 → v2 : données conservées, nouvelles colonnes prêtes',
    () async {
      final migrated = AppDatabase(
        NativeDatabase.memory(
          setup: (raw) {
            for (final sql in _schemaV1) {
              raw.execute(sql);
            }
          },
        ),
      );
      final item = (await migrated.allItems()).single;
      expect(item.content, 'Appeler le médecin');
      expect(item.status, ItemStatus.doing);
      expect(item.priority, ItemPriority.high);
      expect(item.tags, ['santé']);
      expect(
        item.remindAt,
        DateTime.fromMillisecondsSinceEpoch(1790000000 * 1000),
      );
      expect(item.raw, isNull);
      expect(item.context, isNull);
      expect(item.preAlert, isFalse);
      expect((await migrated.allPrefs())['theme'], 'dark');

      final saved = await migrated.saveItem(
        item.copyWith(context: const Value('Santé'), preAlert: true),
      );
      expect(saved.preAlert, isTrue);
      await migrated.close();
    },
  );

  test('la base sur disque est réellement chiffrée (sqlite3mc)', () async {
    final dir = await Directory.systemTemp.createTemp('coffre_test');
    final path = '${dir.path}/chiffre.sqlite';
    const key =
        'aa11bb22cc33dd44ee55ff6600112233445566778899aabbccddeeff00112233';

    final encrypted = sqlite3.open(path);
    applyKey(encrypted, key);
    encrypted.execute(
      "CREATE TABLE t(x TEXT); INSERT INTO t VALUES ('secret');",
    );
    expect(
      encrypted.select('SELECT sqlite3mc_version() AS v').first['v'],
      isNotEmpty,
    );
    encrypted.close();

    // Le texte en clair ne doit pas apparaître dans le fichier.
    final bytes = await File(path).readAsBytes();
    expect(String.fromCharCodes(bytes).contains('secret'), isFalse);

    // Sans la clé : SQLITE_NOTADB.
    final noKey = sqlite3.open(path);
    expect(
      () => noKey.select('SELECT * FROM t'),
      throwsA(isA<SqliteException>()),
    );
    noKey.close();
    await dir.delete(recursive: true);
  });
}

/// Schéma exact de la version 1 (APK déjà installé) : la migration doit
/// ajouter les colonnes v2 sans perdre une seule donnée.
const _schemaV1 = [
  'CREATE TABLE "items" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "kind" TEXT NOT NULL, "status" TEXT NOT NULL DEFAULT \'todo\', "priority" INTEGER NOT NULL DEFAULT 1, "content" TEXT NOT NULL, "tags" TEXT NOT NULL DEFAULT \'[]\', "remind_at" INTEGER NULL, "inbox" INTEGER NOT NULL DEFAULT 1 CHECK ("inbox" IN (0, 1)), "search_text" TEXT NOT NULL DEFAULT \'\', "created_at" INTEGER NOT NULL, "updated_at" INTEGER NOT NULL, "done_at" INTEGER NULL)',
  'CREATE TABLE "prefs" ("key" TEXT NOT NULL, "value" TEXT NOT NULL, PRIMARY KEY ("key"))',
  'CREATE INDEX items_status_idx ON items (status)',
  'CREATE INDEX items_remind_idx ON items (remind_at)',
  "INSERT INTO items (kind, status, priority, content, tags, remind_at, search_text, created_at, updated_at) VALUES ('task', 'doing', 2, 'Appeler le médecin', '[\"santé\"]', 1790000000, ' appeler le medecin sante ', 1780000000, 1780000000)",
  "INSERT INTO prefs VALUES ('theme', 'dark')",
  'PRAGMA user_version = 1',
];
