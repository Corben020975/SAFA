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
const kContexts = [
  'Travail',
  'Santé',
  'Admin',
  'Perso',
  'Déplacement',
  'Hockey',
];

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
