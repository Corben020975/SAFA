import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_services.dart';
import '../../data/database.dart';
import '../../data/enums.dart';
import '../../services/ai/ai_assistant.dart';
import '../../services/secret_store.dart';
import '../theme.dart';

/// Vérifie clé + accord avant tout envoi. Rien ne part sans ce passage.
Future<bool> ensureAiReady(BuildContext context) async {
  final s = AppScope.of(context);
  if (!await s.secrets.has(SecretStore.aiKey)) {
    if (!context.mounted) return false;
    final go = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Assistant IA à configurer'),
        content: const Text(
          'Ajoute ta clé API Claude dans Réglages › Assistant IA. '
          'Elle se crée sur console.anthropic.com (paiement à l\'usage).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: const Text('Plus tard'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(d, true),
            child: const Text('Réglages'),
          ),
        ],
      ),
    );
    if (go == true && context.mounted) {
      Navigator.of(context).pushNamed('/settings');
    }
    return false;
  }
  if (s.settings.aiConsent) return true;
  if (!context.mounted) return false;
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      title: const Text('Avant le premier envoi'),
      content: const Text(
        'L\'assistant envoie le texte choisi à Claude (Anthropic) via Internet, '
        'uniquement quand tu le demandes.\n\n'
        'Avant l\'envoi, Coffre masque les noms précédés d\'une civilité (Mme, M., Dr…), '
        'les n° de registre national, téléphones, e-mails et IBAN, puis les remet dans la réponse.\n\n'
        'Secret professionnel : n\'y mets pas d\'information sensible sur un bénéficiaire '
        '(santé, situation sociale détaillée).',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(d, false),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(d, true),
          child: const Text('J\'ai compris'),
        ),
      ],
    ),
  );
  if (ok == true) await s.settings.setAiConsent(true);
  return ok == true;
}

/// Feuille « Assistant IA » d'un élément.
Future<void> showAiSheet(
  BuildContext context,
  Item item, {
  required ValueChanged<String> onReplace,
  required ValueChanged<String> onAppend,
}) async {
  if (!await ensureAiReady(context) || !context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) =>
        _AiSheet(item: item, onReplace: onReplace, onAppend: onAppend),
  );
}

class _AiSheet extends StatefulWidget {
  const _AiSheet({
    required this.item,
    required this.onReplace,
    required this.onAppend,
  });
  final Item item;
  final ValueChanged<String> onReplace;
  final ValueChanged<String> onAppend;

  @override
  State<_AiSheet> createState() => _AiSheetState();
}

class _AiSheetState extends State<_AiSheet> {
  final _question = TextEditingController();
  AiAction? _action;
  bool _loading = false;
  String? _answer;
  String? _error;

  @override
  void dispose() {
    _question.dispose();
    super.dispose();
  }

  Future<void> _run(AiAction action) async {
    final ai = AppScope.of(context).ai;
    setState(() {
      _action = action;
      _loading = true;
      _answer = null;
      _error = null;
    });
    try {
      final answer = await ai.run(
        action,
        widget.item,
        question: _question.text,
      );
      if (mounted) setState(() => _answer = answer);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createTasks(List<String> steps) async {
    final s = AppScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    for (final step in steps) {
      await s.db.createItem(
        kind: ItemKind.task,
        content: step,
        context: widget.item.context,
      );
    }
    if (!mounted) return;
    Navigator.pop(context);
    messenger.showSnackBar(
      SnackBar(content: Text('${steps.length} tâches ajoutées à l\'Inbox')),
    );
  }

  void _done(String message) {
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final theme = Theme.of(context);
    final masked = AppScope.of(context).settings.aiMask;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome, color: p.sage),
                const SizedBox(width: 10),
                Text('Assistant IA', style: displayStyle(context, 24)),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              masked
                  ? 'Claude · données personnelles masquées avant envoi'
                  : 'Claude · masquage désactivé dans Réglages',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: masked ? p.muted : p.coral,
              ),
            ),
            const SizedBox(height: 18),
            if (_answer == null && !_loading) ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final a in AiAction.values.where(
                    (a) => a != AiAction.ask,
                  ))
                    ActionChip(
                      avatar: Icon(_icon(a), size: 18),
                      label: Text(a.label),
                      onPressed: () => _run(a),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _question,
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'Autre demande (ex. « trouve 3 arguments pour… »)',
                  suffixIcon: IconButton(
                    tooltip: 'Envoyer',
                    icon: const Icon(Icons.arrow_upward),
                    onPressed: () {
                      if (_question.text.trim().isNotEmpty) _run(AiAction.ask);
                    },
                  ),
                ),
              ),
            ],
            if (_loading)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Column(
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 14),
                    Text(
                      '${_action?.label ?? 'Réflexion'}…',
                      style: theme.textTheme.bodyLarge,
                    ),
                  ],
                ),
              ),
            if (_error != null) ...[
              Text(
                _error!,
                style: theme.textTheme.bodyLarge?.copyWith(color: p.coral),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => setState(() => _error = null),
                child: const Text('Retour'),
              ),
            ],
            if (_answer != null) ..._result(context, _answer!),
          ],
        ),
      ),
    );
  }

  List<Widget> _result(BuildContext context, String answer) {
    final p = Palette.of(context);
    final steps = _action == AiAction.steps
        ? AiAssistant.parseSteps(answer)
        : const <String>[];
    return [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: p.field,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: p.line),
        ),
        child: SelectableText(
          answer,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ),
      const SizedBox(height: 14),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (steps.isNotEmpty)
            FilledButton.icon(
              onPressed: () => _createTasks(steps),
              icon: const Icon(Icons.playlist_add_check),
              label: Text('Créer ${steps.length} tâches'),
            ),
          if (_action == AiAction.rewrite)
            FilledButton(
              onPressed: () {
                widget.onReplace(answer);
                _done('Texte remplacé');
              },
              child: const Text('Remplacer le texte'),
            ),
          if (_action == AiAction.message)
            FilledButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: answer));
                _done('Message copié');
              },
              icon: const Icon(Icons.copy),
              label: const Text('Copier'),
            ),
          OutlinedButton(
            onPressed: () {
              widget.onAppend(answer);
              _done('Ajouté à la note');
            },
            child: const Text('Ajouter à la note'),
          ),
          if (_action != AiAction.rewrite)
            OutlinedButton(
              onPressed: () {
                widget.onReplace(answer);
                _done('Texte remplacé');
              },
              child: const Text('Remplacer'),
            ),
          TextButton(
            onPressed: () => setState(() => _answer = null),
            child: const Text('Autre action'),
          ),
        ],
      ),
    ];
  }

  static IconData _icon(AiAction a) => switch (a) {
    AiAction.summarize => Icons.short_text,
    AiAction.develop => Icons.unfold_more,
    AiAction.steps => Icons.checklist,
    AiAction.rewrite => Icons.edit_note,
    AiAction.message => Icons.mail_outline,
    AiAction.ask => Icons.help_outline,
  };
}

/// Brief du jour rédigé par l'IA (sur demande).
Future<void> showDayBriefSheet(BuildContext context, List<Item> open) async {
  if (!await ensureAiReady(context) || !context.mounted) return;
  final future = AppScope.of(context).ai.dayBrief(open, DateTime.now());
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheet) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.95,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, color: Palette.of(context).sage),
              const SizedBox(width: 10),
              Text('Brief du jour', style: displayStyle(context, 24)),
            ],
          ),
          const SizedBox(height: 16),
          FutureBuilder<String>(
            future: future,
            builder: (context, snap) {
              if (snap.hasError) {
                return Text(
                  '${snap.error}',
                  style: TextStyle(color: Palette.of(context).coral),
                );
              }
              if (!snap.hasData) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              return SelectableText(
                snap.data!,
                style: Theme.of(context).textTheme.bodyLarge,
              );
            },
          ),
        ],
      ),
    ),
  );
}
