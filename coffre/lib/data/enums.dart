/// Type d'élément choisi à la capture.
enum ItemKind {
  idea('Idée', 'Idées'),
  task('Tâche', 'Tâches'),
  note('Note', 'Notes');

  const ItemKind(this.label, this.plural);
  final String label;
  final String plural;
}

/// États d'un élément. Pour les idées et notes, seul « Fait » (= traité) a un sens.
enum ItemStatus {
  todo('À faire'),
  doing('En cours'),
  done('Fait');

  const ItemStatus(this.label);
  final String label;
}

/// Stockée en entier (index) pour pouvoir trier par priorité en SQL.
/// Ne jamais réordonner ces valeurs.
enum ItemPriority {
  low('Basse'),
  normal('Normale'),
  high('Haute'),
  urgent('Urgente');

  const ItemPriority(this.label);
  final String label;
}

/// Contextes proposés (détectés automatiquement à la saisie, modifiables).
const kContexts = ['Travail', 'Santé', 'Admin', 'Perso', 'Déplacement'];

enum InboxFilter {
  inbox('Inbox'),
  tasks('Tâches'),
  ideas('Idées'),
  notes('Notes'),
  reminders('Avec rappel'),
  done('Fait');

  const InboxFilter(this.label);
  final String label;
}

enum SortMode {
  recent('Plus récents'),
  priority('Priorité'),
  reminder('Date de rappel');

  const SortMode(this.label);
  final String label;
}

/// Répétition d'un rappel. Quand l'élément est marqué « Fait », il revient
/// à la prochaine date au lieu de se clore.
enum Recurrence {
  none('Jamais', ''),
  daily('Chaque jour', 'chaque jour'),
  weekdays('En semaine (lun–ven)', 'en semaine'),
  weekly('Chaque semaine', 'chaque semaine'),
  biweekly('Toutes les 2 semaines', 'toutes les 2 sem.'),
  monthly('Chaque mois', 'chaque mois'),
  quarterly('Tous les 3 mois', 'tous les 3 mois'),
  yearly('Chaque année', 'chaque année');

  const Recurrence(this.label, this.short);
  final String label;
  final String short;

  /// Première occurrence après [from] ET après [now], à la même heure
  /// (jour du mois conservé, ramené au dernier jour si le mois est court).
  DateTime next(DateTime from, DateTime now) {
    if (this == none) return from;
    for (var k = 1; k < 100000; k++) {
      final candidate = _occurrence(from, k);
      if (candidate.isAfter(now) && candidate.isAfter(from)) return candidate;
    }
    return from;
  }

  DateTime _occurrence(DateTime from, int k) {
    DateTime days(int n) =>
        DateTime(from.year, from.month, from.day + n, from.hour, from.minute);
    return switch (this) {
      none => from,
      daily => days(k),
      weekdays => days(_weekdayOffset(from.weekday, k)),
      weekly => days(7 * k),
      biweekly => days(14 * k),
      monthly => _addMonths(from, k),
      quarterly => _addMonths(from, 3 * k),
      yearly => _addMonths(from, 12 * k),
    };
  }

  /// Nombre de jours pour avancer de [k] jours ouvrables depuis [weekday].
  static int _weekdayOffset(int weekday, int k) {
    var offset = 0, left = k, day = weekday;
    while (left > 0) {
      offset++;
      day = day % 7 + 1;
      if (day <= DateTime.friday) left--;
    }
    return offset;
  }

  static DateTime _addMonths(DateTime d, int months) {
    final index = d.month - 1 + months;
    final year = d.year + index ~/ 12;
    final month = index % 12 + 1;
    final lastDay = DateTime(year, month + 1, 0).day;
    return DateTime(
      year,
      month,
      d.day < lastDay ? d.day : lastDay,
      d.hour,
      d.minute,
    );
  }
}
