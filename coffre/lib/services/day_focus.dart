import '../data/app_settings.dart';
import '../data/database.dart';
import '../data/enums.dart';

/// « Les 3 du jour » : peu de choses, choisies le matin. Le reste attend.
class DayFocus {
  static const size = 3;

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

  static List<Item> suggest(List<Item> open, DateTime now) =>
      ranked(open, now).take(size).toList();

  /// Choix enregistré pour aujourd'hui (éléments encore ouverts), ou null
  /// si le jour a changé.
  static List<Item>? chosen(
    AppSettings settings,
    List<Item> open,
    DateTime now,
  ) {
    if (settings.focusDay != dayKey(now)) return null;
    final byId = {for (final i in open) i.id: i};
    return [for (final id in settings.focusIds) ?byId[id]];
  }

  /// Les 3 du jour ; au premier passage de la journée, la suggestion est
  /// enregistrée pour rester stable (écran et notification de 7 h 30).
  static Future<List<Item>> ensure(
    AppSettings settings,
    List<Item> open,
    DateTime now,
  ) async {
    final existing = chosen(settings, open, now);
    if (existing != null) return existing;
    final picked = suggest(open, now);
    await settings.setFocus(dayKey(now), [for (final i in picked) i.id]);
    return picked;
  }
}
