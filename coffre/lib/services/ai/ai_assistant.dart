import '../../core/date_labels.dart';
import '../../data/app_settings.dart';
import '../../data/database.dart';
import 'ai_engine.dart';
import 'pseudonymizer.dart';

enum AiAction {
  summarize('Synthétiser', 'low'),
  develop('Développer', 'medium'),
  steps('Découper en étapes', 'medium'),
  rewrite('Reformuler', 'low'),
  message('Rédiger un message', 'medium'),
  ask('Autre demande', 'medium');

  const AiAction(this.label, this.effort);
  final String label;

  /// Niveau d'effort Claude : bas pour les tâches simples (réponse rapide).
  final String effort;
}

/// Assistant : n'envoie que ce que tu choisis, jamais automatiquement.
/// Gemini (gratuit) ou Claude (payant) selon les réglages.
class AiAssistant {
  AiAssistant(this._claude, this._gemini, this._settings);
  final AiEngine _claude;
  final AiEngine _gemini;
  final AppSettings _settings;

  AiProvider get provider => _settings.aiProvider;
  AiEngine get _engine => switch (provider) {
    AiProvider.gemini => _gemini,
    AiProvider.claude => _claude,
  };

  static const _base =
      'Tu es l\'assistant de Coffre, le carnet personnel d\'un responsable de '
      'service social (SAFA, CPAS en Belgique). Réponds en français de Belgique, '
      'ton direct, tutoiement, sans formule d\'introduction ni de conclusion. '
      'Les marqueurs entre crochets comme [PERSONNE 1] remplacent des données '
      'personnelles masquées : recopie-les tels quels, n\'invente jamais leur contenu.';

  static String instruction(AiAction action) => switch (action) {
    AiAction.summarize => 'Synthétise l\'essentiel en 3 à 5 puces courtes commençant par « - ». Pas de titre.',
    AiAction.develop =>
      'Développe cette idée ou cette note en un plan concret : objectif, étapes, '
          'points d\'attention. 150 à 250 mots, listes courtes.',
    AiAction.steps =>
      'Découpe en 3 à 8 étapes concrètes, une par ligne, chacune commençant par '
          '« - » puis un verbe d\'action. N\'écris rien d\'autre.',
    AiAction.rewrite =>
      'Reformule ce texte de façon claire et professionnelle en gardant tout le sens. '
          'Renvoie uniquement le texte reformulé.',
    AiAction.message =>
      'Rédige un message court (mail ou SMS) prêt à envoyer à partir de cette note. '
          'Vouvoie le destinataire, ton professionnel et chaleureux. Renvoie uniquement le message.',
    AiAction.ask => 'Réponds à ma demande en t\'appuyant sur cet élément.',
  };

  static String describe(Item item) => [
    'Type : ${item.kind.label}',
    if (item.context != null) 'Contexte : ${item.context}',
    'Priorité : ${item.priority.label.toLowerCase()}',
    if (item.remindAt != null) 'Rappel : ${formatLong(item.remindAt!)}',
    if (item.tags.isNotEmpty) 'Tags : ${item.tags.join(', ')}',
    'Texte :',
    item.content,
  ].join('\n');

  Future<String> run(AiAction action, Item item, {String? question}) {
    final base = instruction(action);
    final request = action == AiAction.ask && (question ?? '').trim().isNotEmpty
        ? '$base\n\nMa demande : ${question!.trim()}'
        : base;
    return _send('$_base\n\n$request', describe(item), action.effort);
  }

  /// Brief du jour à partir des éléments ouverts (titres, dates, contextes).
  Future<String> dayBrief(List<Item> open, DateTime now) {
    final lines = open
        .take(40)
        .map((i) {
          final title = i.content.split('\n').first;
          final when = i.remindAt == null
              ? '-'
              : formatReminder(i.remindAt!, now: now);
          return '${i.kind.label} | ${i.priority.label} | $when | ${i.context ?? '-'} | $title';
        })
        .join('\n');
    return _send(
      '$_base\n\nRédige mon brief du jour, 120 mots maximum, factuel : une phrase '
          'd\'ouverture ; « Priorités : » avec 3 éléments maximum et pourquoi ; '
          '« Peut attendre : » en une ligne ; une idée à ne pas perdre si pertinent.',
      'Nous sommes le ${formatLong(now)}.\nMes éléments ouverts (type | priorité | échéance | contexte | titre) :\n$lines',
      'medium',
    );
  }

  /// Extrait de mail ou de message → une tâche courte, échéance en clair
  /// (relue ensuite par l'analyse locale pour poser le rappel).
  Future<String> toTask(String text) => _send(
    '$_base\n\nTransforme ce texte (extrait de mail ou de message) en UNE tâche '
        'courte pour moi : verbe à l\'infinitif, 12 mots maximum. Si une échéance est '
        'mentionnée, termine par elle en clair (ex. « vendredi », « le 15 octobre », '
        '« fin du mois »). Renvoie uniquement cette ligne.',
    text.trim(),
    'low',
  );

  Future<String> ask(String question) =>
      _send(_base, question.trim(), AiAction.ask.effort);

  Future<String> _send(String system, String content, String effort) async {
    if (!_settings.aiMask) {
      return _engine.complete(system: system, prompt: content, effort: effort);
    }
    final p = Pseudonymizer();
    final answer = await _engine.complete(
      system: system,
      prompt: p.mask(content),
      effort: effort,
    );
    return p.unmask(answer);
  }

  /// Lignes « - … » d'une réponse « étapes » → titres de tâches.
  static List<String> parseSteps(String answer) => answer
      .split('\n')
      .map((l) => l.trim())
      .where(
        (l) =>
            l.startsWith('- ') ||
            l.startsWith('• ') ||
            RegExp(r'^\d+[.)]\s').hasMatch(l),
      )
      .map((l) => l.replaceFirst(RegExp(r'^(?:[-•]|\d+[.)])\s*'), '').trim())
      .where((l) => l.isNotEmpty)
      .toList();
}
