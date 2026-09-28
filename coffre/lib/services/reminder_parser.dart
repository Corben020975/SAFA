import '../core/reminder_defaults.dart';
import '../core/text_normalize.dart';

/// Rappel détecté dans un texte dicté ou tapé (« demain 9h », « dans 20 minutes »).
class ParsedReminder {
  const ParsedReminder(this.when, this.start, this.end);
  final DateTime when;

  /// Position de l'expression dans le texte d'origine (pour la retirer).
  final int start;
  final int end;
}

/// Analyseur volontairement simple, 100 % local. Il PROPOSE un rappel ;
/// l'utilisateur confirme d'un tap. Les heures sont en format 24 h.
class ReminderParser {
  static const _weekdays = {
    'lundi': DateTime.monday,
    'mardi': DateTime.tuesday,
    'mercredi': DateTime.wednesday,
    'jeudi': DateTime.thursday,
    'vendredi': DateTime.friday,
    'samedi': DateTime.saturday,
    'dimanche': DateTime.sunday,
  };

  static const _months = {
    'janvier': 1,
    'fevrier': 2,
    'mars': 3,
    'avril': 4,
    'mai': 5,
    'juin': 6,
    'juillet': 7,
    'aout': 8,
    'septembre': 9,
    'octobre': 10,
    'novembre': 11,
    'decembre': 12,
  };

  static const _numberWords = {
    'un': 1,
    'une': 1,
    'deux': 2,
    'trois': 3,
    'quatre': 4,
    'cinq': 5,
    'six': 6,
    'sept': 7,
    'huit': 8,
    'neuf': 9,
    'dix': 10,
    'onze': 11,
    'douze': 12,
    'quinze': 15,
    'vingt': 20,
    'trente': 30,
    'quarante': 40,
    'quarante-cinq': 45,
  };

  // Heures et minutes par défaut quand seule une partie de journée est dite
  // (matin et soir suivent les réglages).
  static Map<String, (int, int)> get _periods => {
    'matin': ReminderDefaults.morning,
    'midi': (12, 0),
    'apres-midi': (14, 0),
    'apres midi': (14, 0),
    'soir': ReminderDefaults.evening,
  };

  static const _connector = r'(?:(?:pour|a|vers|des|avant|d ici|d.ici)\s+)?';
  static const _time =
      r'(\d{1,2})\s*(?:heures?|h|:)\s*(\d{2})?(?![a-z0-9])|(midi|minuit)';
  static const _numWord =
      r'(\d{1,3}|une?|deux|trois|quatre|cinq|six|sept|huit|neuf|dix|onze|douze|quinze|vingt|trente|quarante-cinq|quarante)';

  static final _relative = RegExp(
    '(?<![a-z])${_connector}dans\\s+(?:(une\\s+demi[- ]heure)|$_numWord\\s*(minutes?|mins?|mn|heures?|h|jours?)(?![a-z]))',
  );

  static final _day = RegExp(
    '(?<![a-z])$_connector('
    r"aujourd.?hui|apres[- ]demain|demain|ce soir|ce matin|cet apres[- ]midi|ce midi|"
    r'(lundi|mardi|mercredi|jeudi|vendredi|samedi|dimanche)(?:\s+prochain)?|'
    r'le\s+(\d{1,2})(?:\s*[/.-]\s*(\d{1,2}))?(?:\s+(janvier|fevrier|mars|avril|mai|juin|juillet|aout|septembre|octobre|novembre|decembre))?'
    r')(?![a-z0-9])',
  );

  // Heure juste après le jour (« demain à 9h », « demain matin »).
  static final _timeAfterDay = RegExp(
    '^[\\s,]*(?:(?:a|vers|pour|des)\\s+)?(?:$_time|(matin|apres[- ]midi|soir|midi))(?![a-z])',
  );

  // Heure seule : exige « à / vers / pour » devant pour éviter « réunion de 2h ».
  static final _timeAlone = RegExp(
    '(?<![a-z])(?:a|vers|pour|des)\\s+(?:$_time)',
  );

  static ParsedReminder? parse(String text, {DateTime? now}) {
    now ??= DateTime.now();
    final folded = foldKeepingLength(text);
    return _parseRelative(folded, now) ??
        _parseDay(folded, now) ??
        _parseTimeAlone(folded, now);
  }

  /// Retire l'expression détectée et nettoie la ponctuation résiduelle.
  static String strip(String text, ParsedReminder parsed) {
    var result =
        '${text.substring(0, parsed.start)} ${text.substring(parsed.end)}';
    result = result
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAllMapped(RegExp(r'\s+([,.;:!?])'), (m) => m.group(1)!)
        .replaceAll(RegExp(r'^[\s,;:.]+|[\s,;:]+$'), '')
        .trim();
    if (result.isEmpty) return text.trim();
    return result[0].toUpperCase() + result.substring(1);
  }

  static ParsedReminder? _parseRelative(String s, DateTime now) {
    final m = _relative.firstMatch(s);
    if (m == null) return null;
    Duration delay;
    if (m.group(1) != null) {
      delay = const Duration(minutes: 30);
    } else {
      final n = _toInt(m.group(2)!);
      if (n == null || n == 0) return null;
      final unit = m.group(3)!;
      if (unit.startsWith('j')) {
        // « dans 3 jours » : ce jour-là à l'heure du matin.
        final (hour, minute) = ReminderDefaults.morning;
        final day = _addDays(
          DateTime(now.year, now.month, now.day, hour, minute),
          n,
        );
        return ParsedReminder(day, m.start, m.end);
      }
      delay = unit.startsWith('h') ? Duration(hours: n) : Duration(minutes: n);
    }
    return ParsedReminder(now.add(delay), m.start, m.end);
  }

  static ParsedReminder? _parseDay(String s, DateTime now) {
    final m = _day.firstMatch(s);
    if (m == null) return null;
    final word = m.group(1)!;
    final today = DateTime(now.year, now.month, now.day);
    DateTime? day;
    (int, int)? time;

    if (word.startsWith('aujourd')) {
      day = today;
    } else if (word.startsWith('apres')) {
      day = _addDays(today, 2);
    } else if (word == 'demain') {
      day = _addDays(today, 1);
    } else if (word.startsWith('ce') || word.startsWith('cet')) {
      day = today;
      final period = word.split(' ').skip(1).join(' ');
      time = _periods[period] ?? _periods[period.replaceAll(' ', '-')];
    } else if (m.group(2) != null) {
      final target = _weekdays[m.group(2)!]!;
      var delta = (target - now.weekday) % 7;
      if (delta == 0) delta = 7; // « lundi » dit un lundi = lundi prochain
      day = _addDays(today, delta);
    } else if (m.group(3) != null) {
      day = _resolveDate(
        now,
        int.parse(m.group(3)!),
        m.group(4) != null ? int.parse(m.group(4)!) : _months[m.group(5)],
      );
    }
    if (day == null) return null;

    var end = m.end;
    final after = _timeAfterDay.firstMatch(s.substring(end));
    if (after != null) {
      final explicit = _readTime(
        after.group(1),
        after.group(2),
        after.group(3),
      );
      final period = after.group(4);
      final t = explicit ?? (period != null ? _periods[period] : null);
      if (t != null) {
        time = t;
        end += after.end;
      }
    }
    time ??= ReminderDefaults.morning;
    final when = DateTime(day.year, day.month, day.day, time.$1, time.$2);
    if (!when.isAfter(now)) return null;
    return ParsedReminder(when, m.start, end);
  }

  static ParsedReminder? _parseTimeAlone(String s, DateTime now) {
    final m = _timeAlone.firstMatch(s);
    if (m == null) return null;
    final t = _readTime(m.group(1), m.group(2), m.group(3));
    if (t == null) return null;
    var when = DateTime(now.year, now.month, now.day, t.$1, t.$2);
    if (!when.isAfter(now)) when = _addDays(when, 1);
    return ParsedReminder(when, m.start, m.end);
  }

  static (int, int)? _readTime(String? hours, String? minutes, String? word) {
    if (word == 'midi') return (12, 0);
    if (word == 'minuit') return (0, 0);
    if (hours == null) return null;
    final h = int.parse(hours);
    final min = minutes == null ? 0 : int.parse(minutes);
    if (h > 23 || min > 59) return null;
    return (h, min);
  }

  static DateTime? _resolveDate(DateTime now, int day, int? month) {
    if (day < 1 || day > 31) return null;
    final today = DateTime(now.year, now.month, now.day);
    if (month == null) {
      // « le 12 » : ce mois-ci, sinon le mois suivant.
      var candidate = DateTime(now.year, now.month, day);
      if (candidate.isBefore(today)) {
        candidate = DateTime(now.year, now.month + 1, day);
      }
      return candidate.day == day ? candidate : null;
    }
    if (month < 1 || month > 12) return null;
    var candidate = DateTime(now.year, month, day);
    if (candidate.isBefore(today)) {
      candidate = DateTime(now.year + 1, month, day);
    }
    return candidate.day == day ? candidate : null;
  }

  /// Ajout de jours calendaires, insensible aux changements d'heure.
  static DateTime _addDays(DateTime d, int days) =>
      DateTime(d.year, d.month, d.day + days, d.hour, d.minute);

  static int? _toInt(String raw) => int.tryParse(raw) ?? _numberWords[raw];
}
