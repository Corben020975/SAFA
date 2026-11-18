import 'package:coffre/data/app_settings.dart';
import 'package:coffre/data/database.dart';
import 'package:coffre/data/enums.dart';
import 'package:coffre/services/day_focus.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'les 3 du jour : retards, priorité, échéance ; choix gardé la journée',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final settings = AppSettings(db);
      await settings.load();
      final now = DateTime.now();
      Future<Item> task(
        String c, {
        DateTime? at,
        ItemPriority p = ItemPriority.normal,
      }) => db.createItem(
        kind: ItemKind.task,
        content: c,
        remindAt: at,
        priority: p,
      );

      final week = await task(
        'Dans 5 jours',
        at: now.add(const Duration(days: 5)),
      );
      final late = await task(
        'En retard',
        at: now.subtract(const Duration(days: 1)),
      );
      final high = await task('Haute', p: ItemPriority.high);
      await db.createItem(kind: ItemKind.idea, content: 'Idée');
      await task('Sans date');

      final open = await db.allItems();
      final focus = await DayFocus.ensure(settings, open, now);
      expect(
        [for (final i in focus) i.content],
        ['En retard', 'Haute', 'Dans 5 jours'],
      );
      expect(settings.focusIds, [late.id, high.id, week.id]);

      // Une tâche faite sort des 3 sans en ramener une autre le même jour.
      await db.setStatus(late.id, ItemStatus.done);
      final reopened = (await db.allItems())
          .where((i) => i.status != ItemStatus.done)
          .toList();
      expect(
        [for (final i in DayFocus.chosen(settings, reopened, now)!) i.content],
        ['Haute', 'Dans 5 jours'],
      );
      // Le lendemain : nouvelle sélection.
      expect(
        DayFocus.chosen(settings, reopened, now.add(const Duration(days: 1))),
        isNull,
      );
      await db.close();
    },
  );

  test('Pro et Perso : deux listes séparées, sans contexte = Pro', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final settings = AppSettings(db);
    await settings.load();
    final now = DateTime(2026, 11, 18, 8); // mercredi
    await db.createItem(
      kind: ItemKind.task,
      content: 'Facture Engie',
      context: 'Perso',
      tags: ['gmail', 'facture'],
      priority: ItemPriority.high,
    );
    await db.createItem(kind: ItemKind.task, content: 'Note DG');
    await db.createItem(
      kind: ItemKind.task,
      content: 'Suivi Bachar',
      tags: ['notion', 'suivi'],
    );
    final open = await db.allItems();
    final pro = await DayFocus.ensure(settings, open, now, FocusSide.pro);
    final perso = await DayFocus.ensure(settings, open, now, FocusSide.perso);
    expect([for (final i in pro) i.content]..sort(), [
      'Note DG',
      'Suivi Bachar',
    ]);
    expect([for (final i in perso) i.content], ['Facture Engie']);
    expect(DayFocus.order(now).first, FocusSide.pro);
    // Un ancien choix mélangé est ignoré : nouvelle suggestion du bon côté.
    await settings.setFocus(DayFocus.dayKey(now), [for (final i in open) i.id]);
    expect(DayFocus.chosen(settings, open, now), isNull);
    expect(
      [for (final i in await DayFocus.ensure(settings, open, now)) i.content]
        ..sort(),
      ['Note DG', 'Suivi Bachar'],
    );
    expect(DayFocus.order(DateTime(2026, 11, 21)).first, FocusSide.perso);
    await db.close();
  });
}
