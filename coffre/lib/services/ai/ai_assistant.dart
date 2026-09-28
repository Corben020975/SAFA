import '../../core/date_labels.dart';
import '../../data/app_settings.dart';
import '../../data/database.dart';
import 'claude_client.dart';
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
class AiAssistant {
  AiAssistant(this._claude, this._settings);
  final ClaudeClient _claude;
  final AppSettings _settings;

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
    final request = action == AiAction.ask && (question ?? '').trim().isNotEmpty
        ? '${instruction(action)}\n\nMa demande : ${question!.trim()}'
        : instruction(action);
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

  Future<String> ask(String question) =>
      _send(_base, question.trim(), AiAction.ask.effort);

  Future<String> _send(String system, String content, String effort) async {
    if (!_settings.aiMask) {
      return _claude.complete(system: system, prompt: content, effort: effort);
    }
    final p = Pseudonymizer();
    final answer = await _claude.complete(
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
