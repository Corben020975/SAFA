import '../core/reminder_defaults.dart';
import '../core/text_normalize.dart';
import '../data/enums.dart';
import 'reminder_parser.dart';

/// Lecture d'une saisie brute, entièrement sur le téléphone (aucune IA en ligne).
class Analysis {
  const Analysis({
    required this.kind,
    required this.title,
    required this.priority,
    this.remindAt,
    this.recurrence = Recurrence.none,
    this.context,
    this.raw,
  });

  final ItemKind kind;

  /// Texte nettoyé (formules d'amorce et date retirées).
  final String title;
  final ItemPriority priority;
  final DateTime? remindAt;
  final Recurrence recurrence;
  final String? context;

  /// Texte d'origine, seulement s'il diffère du titre.
  final String? raw;
}

class CaptureAnalyzer {
  static final _ideaLead = RegExp(r'^(une\s+)?idee\b|\b(idee de|et si)\b');
  static final _reminderWords = RegExp(
    r"\b(rappelle|rappel|pense a|n'oublie|noublie)\b",
  );
  static final _taskWords = RegExp(
    r'\b(appeler|appelle|telephoner|faut que|il faut|envoyer|envoie|payer|acheter|'
    r'reserver|finir|terminer|preparer|ecrire|signer|deposer|rendre|livrer|reunion|'
    r'rendez-vous|rdv|train|relancer|verifier|imprimer|commander|prendre)\b',
  );
  static final _deadline = RegExp(
    r"\b(echeance|deadline|avant le|d'ici|dici)\b",
  );
  static final _noteLead = RegExp(r'^note\s*[:\-—]');
  static final _urgent = RegExp(
    r'\b(urgent|urgente|asap|tout de suite|immediatement)\b',
  );
  static final _important = RegExp(r'\b(important|importante|prioritaire)\b');

  // Contextes, dans l'ordre de priorité. Mots repliés (sans accents).
  static final _contexts = <(String, RegExp)>[
    ('Hockey', RegExp(r'\b(hockey|red lions|entrainement|match)\b')),
    (
      'Santé',
      RegExp(
        r'\b(dentiste|medecin|docteur|pharmacie|sante|hopital|ordonnance|kine|mutuelle)\b',
      ),
    ),
    (
      'Admin',
      RegExp(
        r'\b(impot|impots|facture|factures|banque|loyer|assurance|admin|taxe|amende|contrat)\b',
      ),
    ),
    (
      'Déplacement',
      RegExp(
        r'\b(bruxelles|braine|amsterdam|sncb|train|thalys|eurostar|gare|avion|vol)\b',
      ),
    ),
    (
      'Travail',
      RegExp(
        r'\b(boulot|travail|bureau|client|reunion|collegue|cpas|safa|equipe|waterloo|beneficiaire|conseil)\b',
      ),
    ),
    (
      'Perso',
      RegExp(
        r'\b(famille|maison|enfant|enfants|courses|pain|cuisine|anniversaire|jardin)\b',
      ),
    ),
  ];
  static final _folder = RegExp(r'\bdossier\b');
  static final _folderPhrase = RegExp(r'\b(de|un|du|sans)\s+dossier\b');

  // Formules d'amorce retirées du titre (répétées : « urgent : il faut que je… »).
  static final _lead = RegExp(
    r"^(?:s'il te pla[iî]t,?\s*|stp,?\s*)?(?:urgent\s*[:\-—]\s*)?"
    r"(?:il faut que je |il faut que j'|il faut |faut que je |faut que j'|"
    r"rappelle[- ]moi de |rappelle[- ]moi d'|rappelle[- ]moi |pense à |pense a |"
    r"n'oublie pas de |n’oublie pas de |idée\s*[:\-—]\s*|idee\s*[:\-—]\s*|"
    r"note\s*[:\-—]\s*|[ée]ch[ée]ance\s*[:\-—,]?\s*)",
    caseSensitive: false,
  );

  static Analysis analyze(String input, {DateTime? now}) {
    now ??= DateTime.now();
    final text = input.replaceAll(RegExp(r'[ \t]+'), ' ').trim();
    final folded = foldKeepingLength(text);

    // « chaque lundi à 9h » : la répétition d'abord, puis la date.
    final repeat = ReminderParser.extractRecurrence(text);
    final source = repeat?.text ?? text;
    final reminder = ReminderParser.parse(source, now: now);
    var title = reminder != null
        ? ReminderParser.strip(source, reminder)
        : source;
    final remindAt =
        reminder?.when ??
        (repeat == null
            ? null
            : ReminderParser.firstAt(
                repeat.time ?? ReminderDefaults.morning,
                now,
                repeat.recurrence,
              ));
    for (var i = 0; i < 3; i++) {
      title = title.replaceFirst(_lead, '');
    }
    title = title
        .replaceAll(
          RegExp(
            r'\b(urgent|urgente|asap)\b\s*[:\-—]?\s*',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .replaceAll(RegExp(r'^[\s,.:;\-—]+|[\s,;:\-—]+$'), '')
        .trim();
    if (title.isEmpty) title = text;
    title = title[0].toUpperCase() + title.substring(1);

    final kind = _kindOf(folded, hasDate: remindAt != null);
    return Analysis(
      kind: kind,
      title: title,
      priority: _priorityOf(folded, kind, remindAt, now),
      remindAt: remindAt,
      recurrence: repeat?.recurrence ?? Recurrence.none,
      context: _contextOf(folded),
      raw: title == text ? null : text,
    );
  }

  static ItemKind _kindOf(String folded, {required bool hasDate}) {
    final idea = _ideaLead.hasMatch(folded);
    final task =
        _taskWords.hasMatch(folded) ||
        _deadline.hasMatch(folded) ||
        _reminderWords.hasMatch(folded);
    if (_noteLead.hasMatch(folded)) return ItemKind.note;
    if (idea && !task && !_deadline.hasMatch(folded)) return ItemKind.idea;
    if (task || hasDate) return ItemKind.task;
    if (idea) return ItemKind.idea;
    return ItemKind.note;
  }

  static ItemPriority _priorityOf(
    String folded,
    ItemKind kind,
    DateTime? due,
    DateTime now,
  ) {
    if (_urgent.hasMatch(folded)) return ItemPriority.urgent;
    if (_important.hasMatch(folded)) return ItemPriority.high;
    // Tâche à échéance proche : haute (logique Sillage, 36 h).
    if (kind == ItemKind.task &&
        due != null &&
        due.difference(now).inHours < 36) {
      return ItemPriority.high;
    }
    return ItemPriority.normal;
  }

  static String? _contextOf(String folded) {
    for (final (label, pattern) in _contexts) {
      if (pattern.hasMatch(folded)) return label;
    }
    if (_folder.hasMatch(folded) && !_folderPhrase.hasMatch(folded)) {
      return 'Travail';
    }
    return null;
  }
}
