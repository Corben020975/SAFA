/// Heures utilisées quand seule une date est donnée (« demain », « lundi »)
/// ou une partie de journée (« ce soir »). Réglables dans Réglages.
class ReminderDefaults {
  static (int, int) morning = (9, 0);
  static (int, int) evening = (18, 0);

  static String label((int, int) t) =>
      '${t.$1.toString().padLeft(2, '0')}:${t.$2.toString().padLeft(2, '0')}';
}
