import 'dart:convert';

import 'package:drift/drift.dart';

import '../core/text_normalize.dart';
import 'enums.dart';

part 'database.g.dart';

/// Tags stockés en JSON dans une seule colonne : suffisant pour un usage
/// mono-utilisateur (quelques milliers d'éléments), pas de table de jointure.
class TagsConverter extends TypeConverter<List<String>, String> {
  const TagsConverter();

  @override
  List<String> fromSql(String fromDb) {
    try {
      final decoded = jsonDecode(fromDb);
      if (decoded is List) return decoded.whereType<String>().toList();
    } catch (_) {}
    return const [];
  }

  @override
  String toSql(List<String> value) => jsonEncode(value);
}

@DataClassName('Item')
@TableIndex(name: 'items_status_idx', columns: {#status})
@TableIndex(name: 'items_remind_idx', columns: {#remindAt})
class Items extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get kind => textEnum<ItemKind>()();
  TextColumn get status =>
      textEnum<ItemStatus>().withDefault(Constant(ItemStatus.todo.name))();
  IntColumn get priority => intEnum<ItemPriority>().withDefault(
    Constant(ItemPriority.normal.index),
  )();
  TextColumn get content => text()();
  TextColumn get tags =>
      text().map(const TagsConverter()).withDefault(const Constant('[]'))();
  DateTimeColumn get remindAt => dateTime().nullable()();

  /// true tant que l'élément n'a pas été « classé » depuis l'Inbox.
  BoolColumn get inbox => boolean().withDefault(const Constant(true))();

  /// Texte tel que tapé ou dicté, quand l'analyse l'a nettoyé (« Brut »).
  TextColumn get raw => text().nullable()();

  /// Contexte : Travail, Santé, Admin… (détecté à la saisie, modifiable).
  TextColumn get context => text().nullable()();

  /// Notification supplémentaire 1 h 30 avant le rappel.
  BoolColumn get preAlert => boolean().withDefault(const Constant(false))();

  /// Événement créé dans l'agenda du téléphone (Google Agenda synchronisé).
  IntColumn get calendarEventId => integer().nullable()();

  /// Page Notion créée depuis cet élément.
  TextColumn get notionUrl => text().nullable()();

  /// Contenu + tags normalisés (voir text_normalize.dart), pour la recherche.
  TextColumn get searchText => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get doneAt => dateTime().nullable()();
}

/// Réglages clé/valeur : évite une dépendance supplémentaire (shared_preferences).
@DataClassName('Pref')
class Prefs extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(tables: [Items, Prefs])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    // Chaque version ajoute des colonnes sans toucher aux données existantes.
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.addColumn(items, items.raw);
        await m.addColumn(items, items.context);
        await m.addColumn(items, items.preAlert);
      }
      if (from < 3) {
        await m.addColumn(items, items.calendarEventId);
        await m.addColumn(items, items.notionUrl);
      }
    },
  );

  // ---------------------------------------------------------------------------
  // Lecture
  // ---------------------------------------------------------------------------

  Stream<List<Item>> watchList(InboxFilter filter, SortMode sort) {
    final query = select(items)..where((t) => _filterExpr(t, filter));
    query.orderBy(_ordering(sort, filter));
    return query.watch();
  }

  /// Recherche sur tous les éléments (y compris faits), tous mots requis.
  Stream<List<Item>> watchSearch(String rawQuery) {
    final words = searchWords(rawQuery);
    final query = select(items);
    for (final word in words) {
      // `word` ne contient que [a-z0-9] : aucun joker LIKE parasite possible.
      query.where((t) => t.searchText.like('%$word%'));
    }
    query
      ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)])
      ..limit(200);
    return query.watch();
  }

  Stream<Map<InboxFilter, int>> watchCounts() {
    const done = "'done'";
    return customSelect(
      'SELECT '
      'COALESCE(SUM(CASE WHEN inbox = 1 AND status <> $done THEN 1 END), 0) AS c_inbox, '
      "COALESCE(SUM(CASE WHEN kind = 'task' AND status <> $done THEN 1 END), 0) AS c_tasks, "
      "COALESCE(SUM(CASE WHEN kind = 'idea' AND status <> $done THEN 1 END), 0) AS c_ideas, "
      "COALESCE(SUM(CASE WHEN kind = 'note' AND status <> $done THEN 1 END), 0) AS c_notes, "
      'COALESCE(SUM(CASE WHEN remind_at IS NOT NULL AND status <> $done THEN 1 END), 0) AS c_rem, '
      'COALESCE(SUM(CASE WHEN status = $done THEN 1 END), 0) AS c_done '
      'FROM items',
      readsFrom: {items},
    ).watchSingle().map(
      (row) => {
        InboxFilter.inbox: row.read<int>('c_inbox'),
        InboxFilter.tasks: row.read<int>('c_tasks'),
        InboxFilter.ideas: row.read<int>('c_ideas'),
        InboxFilter.notes: row.read<int>('c_notes'),
        InboxFilter.reminders: row.read<int>('c_rem'),
        InboxFilter.done: row.read<int>('c_done'),
      },
    );
  }

  /// Tout ce qui n'est pas fait : base de la vue « Jour ».
  Stream<List<Item>> watchOpen() =>
      (select(items)
            ..where((t) => t.status.equalsValue(ItemStatus.done).not())
            ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
          .watch();

  Stream<Item?> watchItem(int id) =>
      (select(items)..where((t) => t.id.equals(id))).watchSingleOrNull();

  Future<Item?> getItem(int id) =>
      (select(items)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Rappels encore à venir : source de vérité pour resynchroniser les alarmes.
  Future<List<Item>> pendingReminders() {
    final now = DateTime.now();
    return (select(items)..where(
          (t) =>
              t.remindAt.isBiggerThanValue(now) &
              t.status.equalsValue(ItemStatus.done).not(),
        ))
        .get();
  }

  Future<List<Item>> allItems() =>
      (select(items)..orderBy([(t) => OrderingTerm.asc(t.id)])).get();

  // ---------------------------------------------------------------------------
  // Écriture
  // ---------------------------------------------------------------------------

  Future<Item> createItem({
    required ItemKind kind,
    required String content,
    ItemPriority priority = ItemPriority.normal,
    List<String> tags = const [],
    DateTime? remindAt,
    String? raw,
    String? context,
    bool preAlert = false,
    ItemStatus status = ItemStatus.todo,
    bool inbox = true,
    String? notionUrl,
  }) async {
    final now = DateTime.now();
    final id = await into(items).insert(
      ItemsCompanion.insert(
        kind: kind,
        content: content.trim(),
        status: Value(status),
        inbox: Value(inbox),
        notionUrl: Value(notionUrl),
        priority: Value(priority),
        tags: Value(tags),
        remindAt: Value(remindAt),
        raw: Value(raw),
        context: Value(context),
        preAlert: Value(preAlert),
        searchText: Value(buildSearchText(content, [...tags, ?context])),
        createdAt: now,
        updatedAt: now,
      ),
    );
    return (await getItem(id))!;
  }

  /// Enregistre l'élément complet (écran Détail). Recalcule l'index de
  /// recherche, la date de modification et la date « fait ».
  Future<Item> saveItem(Item item) async {
    final now = DateTime.now();
    final saved = item.copyWith(
      content: item.content.trim(),
      searchText: buildSearchText(item.content, [...item.tags, ?item.context]),
      updatedAt: now,
      doneAt: Value(
        item.status == ItemStatus.done ? (item.doneAt ?? now) : null,
      ),
    );
    await update(items).replace(saved);
    return saved;
  }

  Future<Item?> setStatus(int id, ItemStatus status) async {
    final item = await getItem(id);
    if (item == null) return null;
    return saveItem(item.copyWith(status: status));
  }

  Future<Item?> setInbox(int id, bool inInbox) async {
    final item = await getItem(id);
    if (item == null) return null;
    return saveItem(item.copyWith(inbox: inInbox));
  }

  /// « Plus tard » depuis une carte : déplace le rappel.
  Future<Item?> setReminder(int id, DateTime? at) async {
    final item = await getItem(id);
    if (item == null) return null;
    return saveItem(item.copyWith(remindAt: Value(at)));
  }

  /// Reporte le rappel à maintenant + [delay] (action « snooze » de la notification).
  Future<Item?> snooze(int id, Duration delay) async {
    final item = await getItem(id);
    if (item == null || item.status == ItemStatus.done) return null;
    return saveItem(item.copyWith(remindAt: Value(DateTime.now().add(delay))));
  }

  Future<void> deleteItem(int id) =>
      (delete(items)..where((t) => t.id.equals(id))).go();

  /// Réinsère un élément supprimé (bouton « Annuler »), avec son id d'origine.
  Future<void> restoreItem(Item item) =>
      into(items).insert(item, mode: InsertMode.insertOrReplace);

  /// Import d'une sauvegarde : ignore les doublons (même date de création
  /// et même contenu). Retourne les éléments réellement ajoutés.
  /// Liens Notion déjà connus (envoyés ou importés) : pas de doublon.
  Future<Set<String>> notionUrls() async {
    final query = selectOnly(items)
      ..addColumns([items.notionUrl])
      ..where(items.notionUrl.isNotNull());
    return {for (final row in await query.get()) row.read(items.notionUrl)!};
  }

  Future<List<Item>> importItems(List<ItemsCompanion> incoming) {
    return transaction(() async {
      final added = <Item>[];
      for (final entry in incoming) {
        final exists =
            await (select(items)..where(
                  (t) =>
                      t.createdAt.equals(entry.createdAt.value) &
                      t.content.equals(entry.content.value),
                ))
                .getSingleOrNull();
        if (exists != null) continue;
        final id = await into(items).insert(entry);
        added.add((await getItem(id))!);
      }
      return added;
    });
  }

  // ---------------------------------------------------------------------------
  // Réglages
  // ---------------------------------------------------------------------------

  Future<Map<String, String>> allPrefs() async {
    final rows = await select(prefs).get();
    return {for (final row in rows) row.key: row.value};
  }

  Future<void> setPref(String key, String value) => into(prefs)
      .insertOnConflictUpdate(PrefsCompanion.insert(key: key, value: value));

  // ---------------------------------------------------------------------------
  // Filtres et tris
  // ---------------------------------------------------------------------------

  Expression<bool> _filterExpr($ItemsTable t, InboxFilter filter) {
    final notDone = t.status.equalsValue(ItemStatus.done).not();
    return switch (filter) {
      InboxFilter.inbox => t.inbox.equals(true) & notDone,
      InboxFilter.tasks => t.kind.equalsValue(ItemKind.task) & notDone,
      InboxFilter.ideas => t.kind.equalsValue(ItemKind.idea) & notDone,
      InboxFilter.notes => t.kind.equalsValue(ItemKind.note) & notDone,
      InboxFilter.reminders => t.remindAt.isNotNull() & notDone,
      InboxFilter.done => t.status.equalsValue(ItemStatus.done),
    };
  }

  List<OrderClauseGenerator<$ItemsTable>> _ordering(
    SortMode sort,
    InboxFilter filter,
  ) {
    return switch (sort) {
      SortMode.recent when filter == InboxFilter.done => [
        (t) => OrderingTerm.desc(t.doneAt, nulls: NullsOrder.last),
        (t) => OrderingTerm.desc(t.createdAt),
      ],
      SortMode.recent => [(t) => OrderingTerm.desc(t.createdAt)],
      SortMode.priority => [
        (t) => OrderingTerm.desc(t.priority),
        (t) => OrderingTerm.asc(t.remindAt, nulls: NullsOrder.last),
        (t) => OrderingTerm.desc(t.createdAt),
      ],
      SortMode.reminder => [
        (t) => OrderingTerm.asc(t.remindAt, nulls: NullsOrder.last),
        (t) => OrderingTerm.desc(t.createdAt),
      ],
    };
  }
}
