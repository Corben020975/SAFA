import 'package:intl/intl.dart';

/// Écart en jours calendaires. Calculé en UTC pour ne pas perdre un jour
/// lors du passage heure d'été / heure d'hiver (jour de 23 h ou 25 h).
int calendarDaysBetween(DateTime from, DateTime to) {
  final a = DateTime.utc(from.year, from.month, from.day);
  final b = DateTime.utc(to.year, to.month, to.day);
  return b.difference(a).inDays;
}

String _capitalize(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// « Aujourd'hui 14:30 », « Demain 09:00 », « Jeudi 09:00 », « 12 oct. · 09:00 ».
String formatReminder(DateTime dt, {DateTime? now}) {
  now ??= DateTime.now();
  final days = calendarDaysBetween(now, dt);
  final time = DateFormat.Hm('fr').format(dt);
  if (days == 0) return "Aujourd'hui $time";
  if (days == 1) return 'Demain $time';
  if (days == -1) return 'Hier $time';
  if (days > 1 && days < 7) {
    return '${_capitalize(DateFormat.EEEE('fr').format(dt))} $time';
  }
  if (dt.year == now.year) return '${DateFormat('d MMM', 'fr').format(dt)} · $time';
  return '${DateFormat('d MMM y', 'fr').format(dt)} · $time';
}

/// « lundi 28 septembre 2026 à 10:00 »
String formatLong(DateTime dt) =>
    DateFormat("EEEE d MMMM y 'à' HH:mm", 'fr').format(dt);

String formatFileStamp(DateTime dt) => DateFormat('yyyy-MM-dd_HHmm').format(dt);
