import '../core/life_domain.dart';
import '../data/app_settings.dart';
import '../data/database.dart';
import '../data/enums.dart';

/// Deux listes : les 3 du jour Pro et les 3 du jour Perso.
enum FocusSide {
  pro('Pro'),
  perso('Perso');

  const FocusSide(this.label);
  final String label;

  bool get isPerso => this == FocusSide.perso;
}

/// « Les 3 du jour » : peu de choses, choisies le matin. Le reste attend.
class DayFocus {
  static const size = 3;

  /// Week-end : le bloc Perso passe en premier.
  static List<FocusSide> order(DateTime now) => now.weekday >= DateTime.saturday
      ? const [FocusSide.perso, FocusSide.pro]
      : const [FocusSide.pro, FocusSide.perso];

  /// Éléments du côté demandé (sans contexte = Pro).
  static List<Item> forSide(List<Item> open, FocusSide side) => [
    for (final i in open)
      if (itemIsPerso(i) == side.isPerso) i,
  ];

  static String dayKey(DateTime d) => '${d.year}-${d.month}-${d.day}';

  /// Ordre de suggestion : retards, puis priorité, puis échéance du jour,
  /// puis « en cours », puis le plus récent.
  static List<Item> ranked(List<Item> open, DateTime now) {
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    int group(Item i) {
      final at = i.remindAt;
      if (at != null && at.isBefore(now)) return 0;
      if (i.priority.index >= ItemPriority.high.index) return 1;
      if (at != null && at.isBefore(tomorrow)) return 2;
      if (i.status == ItemStatus.doing) return 3;
      return 4;
    }

    final tasks =
        open
            .where(
              (i) => i.kind == ItemKind.task && i.status != ItemStatus.done,
            )
            .toList()
          ..sort((a, b) {
            final g = group(a).compareTo(group(b));
            if (g != 0) return g;
            final p = b.priority.index.compareTo(a.priority.index);
            if (p != 0) return p;
            final aa = a.remindAt, ba = b.remindAt;
            if (aa != null && ba != null) return aa.compareTo(ba);
            if (aa != null) return -1;
            if (ba != null) return 1;
            return b.createdAt.compareTo(a.createdAt);
          });
    return tasks;
  }

  static List<Item> suggest(
    List<Item> open,
    DateTime now, [
    FocusSide side = FocusSide.pro,
  ]) => ranked(forSide(open, side), now).take(size).toList();

  /// Choix enregistré pour aujourd'hui (éléments encore ouverts), ou null
  /// si le jour a changé.
  static List<Item>? chosen(
    AppSettings settings,
    List<Item> open,
    DateTime now, [
    FocusSide side = FocusSide.pro,
  ]) {
    final day = side.isPerso ? settings.focusPersoDay : settings.focusDay;
    if (day != dayKey(now)) return null;
    final ids = side.isPerso ? settings.focusPersoIds : settings.focusIds;
    final byId = {for (final i in open) i.id: i};
    return [for (final id in ids) ?byId[id]];
  }

  /// Les 3 du jour ; au premier passage de la journée, la suggestion est
  /// enregistrée pour rester stable (écran et notification de 7 h 30).
  static Future<List<Item>> ensure(
    AppSettings settings,
    List<Item> open,
    DateTime now, [
    FocusSide side = FocusSide.pro,
  ]) async {
    final existing = chosen(settings, open, now, side);
    if (existing != null) return existing;
    final picked = suggest(open, now, side);
    await settings.setFocus(dayKey(now), [
      for (final i in picked) i.id,
    ], perso: side.isPerso);
    return picked;
  }
}
