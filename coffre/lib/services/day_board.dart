import '../core/date_labels.dart';
import '../core/reminder_defaults.dart';
import '../data/database.dart';
import '../data/enums.dart';

/// Vue « Jour » : répartit les éléments ouverts par urgence (logique reprise
/// de Sillage) et rédige un court brief, calculé localement.
class DayBoard {
  DayBoard._({
    required this.now,
    required this.soonItems,
    required this.todayItems,
    required this.nextItems,
    required this.undatedItems,
    required this.spark,
    required this.laterCount,
    required this.openCount,
  });

  final DateTime now;

  /// En retard, dans les 3 heures, pré-alerte atteinte, ou urgent sans date.
  final List<Item> soonItems;
  final List<Item> todayItems;

  /// Dans les 7 prochains jours.
  final List<Item> nextItems;

  /// Tâches sans date.
  final List<Item> undatedItems;

  /// Idée ou note récente « à ne pas perdre ».
  final Item? spark;

  /// Échéances au-delà de 7 jours.
  final int laterCount;
  final int openCount;

  static const preAlertLead = Duration(minutes: 90);

  factory DayBoard.compute(List<Item> items, DateTime now) {
    final open = items.where((i) => i.status != ItemStatus.done).toList();
    final soon = <Item>[],
        today = <Item>[],
        next = <Item>[],
        undated = <Item>[];
    var later = 0;
    final shelf = <Item>[];

    for (final item in open) {
      final due = item.remindAt;
      if (due == null) {
        if (item.priority.index >= ItemPriority.high.index) {
          soon.add(item);
        } else if (item.kind == ItemKind.task) {
          undated.add(item);
        } else {
          shelf.add(item);
        }
        continue;
      }
      final untilDue = due.difference(now);
      final preAlertReached =
          item.preAlert && !now.isBefore(due.subtract(preAlertLead));
      final days = calendarDaysBetween(now, due);
      if (untilDue.inMinutes <= 180 || preAlertReached) {
        soon.add(item);
      } else if (days == 0) {
        today.add(item);
      } else if (days <= 7) {
        next.add(item);
      } else {
        later++;
      }
    }

    for (final list in [soon, today, next, undated]) {
      list.sort(_byUrgency);
    }
    final recentLimit = now.subtract(const Duration(days: 14));
    final recent = shelf.where((i) => i.createdAt.isAfter(recentLimit)).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final spark =
        recent.where((i) => i.kind == ItemKind.idea).firstOrNull ??
        recent.firstOrNull;

    return DayBoard._(
      now: now,
      soonItems: soon,
      todayItems: today,
      nextItems: next,
      undatedItems: undated,
      spark: spark,
      laterCount: later,
      openCount: open.length,
    );
  }

  bool get isEmpty => openCount == 0;

  /// Grande phrase d'en-tête, factuelle.
  String get headline {
    if (openCount == 0) return 'Rien en cours.';
    final urgent = soonItems.length;
    final day = urgent + todayItems.length;
    if (urgent > 0) {
      return urgent == 1 ? '1 chose maintenant.' : '$urgent choses maintenant.';
    }
    if (day == 0) return 'Rien dans l\'immédiat.';
    return day == 1 ? '1 chose aujourd\'hui.' : '$day choses aujourd\'hui.';
  }

  /// Ce qui peut attendre, en une ligne.
  String get laterLine {
    final bits = <String>[];
    if (nextItems.length == 1) bits.add('une cette semaine');
    if (nextItems.length > 1) bits.add('${nextItems.length} cette semaine');
    if (undatedItems.length == 1) bits.add('une tâche sans date');
    if (undatedItems.length > 1) {
      bits.add('${undatedItems.length} tâches sans date');
    }
    if (laterCount == 1) bits.add('une plus loin');
    if (laterCount > 1) bits.add('$laterCount plus loin');
    return bits.isEmpty
        ? 'Rien d\'autre en attente.'
        : 'Ensuite : ${bits.join(', ')}.';
  }

  static int _byUrgency(Item a, Item b) {
    final p = b.priority.index.compareTo(a.priority.index);
    if (p != 0) return p;
    final ad = a.remindAt?.millisecondsSinceEpoch ?? 1 << 62;
    final bd = b.remindAt?.millisecondsSinceEpoch ?? 1 << 62;
    return ad.compareTo(bd);
  }
}

/// Choix de « Plus tard » (repris de Sillage), calculés à l'instant.
List<(String, DateTime)> laterChoices(DateTime now) {
  final (eh, em) = ReminderDefaults.evening;
  final (mh, mm) = ReminderDefaults.morning;
  final tonight = DateTime(now.year, now.month, now.day, eh, em);
  final beforeEvening = now.isBefore(tonight);
  return [
    ('Dans 2 h', now.add(const Duration(hours: 2))),
    (
      beforeEvening ? 'Ce soir' : 'Demain soir',
      beforeEvening
          ? tonight
          : DateTime(now.year, now.month, now.day + 1, eh, em),
    ),
    ('Demain matin', DateTime(now.year, now.month, now.day + 1, mh, mm)),
  ];
}
