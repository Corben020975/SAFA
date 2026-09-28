import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../core/date_labels.dart';
import '../../services/capture_analyzer.dart';
import '../../services/notification_service.dart';
import '../screens/capture_screen.dart';
import '../theme.dart';
import 'dictation_button.dart';
import 'reminder_field.dart';

/// Barre de capture toujours visible en bas (vues Jour et Flux).
/// Texte ou dictée → aperçu de l'analyse → envoi. Rien n'est enregistré
/// sans ton geste : la dictée remplit le champ, tu relis, tu envoies.
class QuickComposer extends StatefulWidget {
  const QuickComposer({
    super.key,
    required this.controller,
    required this.focusNode,
  });
  final TextEditingController controller;
  final FocusNode focusNode;

  @override
  State<QuickComposer> createState() => _QuickComposerState();
}

class _QuickComposerState extends State<QuickComposer> {
  Analysis? _preview;
  bool _saving = false;

  /// Rappel choisi à la main (remplace celui détecté), ou retiré.
  DateTime? _customAt;
  bool _noReminder = false;

  DateTime? get _reminder =>
      _noReminder ? null : (_customAt ?? _preview?.remindAt);

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    final text = widget.controller.text.trim();
    setState(() {
      _preview = text.isEmpty ? null : CaptureAnalyzer.analyze(text);
      if (text.isEmpty) {
        _customAt = null;
        _noReminder = false;
      }
    });
  }

  Future<void> _adjustReminder() async {
    final chosen = await pickReminderDateTime(context, _reminder);
    if (chosen == null || !mounted) return;
    setState(() {
      _customAt = chosen;
      _noReminder = false;
    });
  }

  void _onDictated(String dictated) {
    if (!mounted) return;
    final updated = appendDictation(widget.controller.text, dictated);
    widget.controller.value = TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(offset: updated.length),
    );
  }

  Future<void> _send() async {
    final text = widget.controller.text.trim();
    if (text.isEmpty || _saving) return;
    final s = AppScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _saving = true);
    if (s.speech.isListening) await s.speech.stop();

    final a = CaptureAnalyzer.analyze(text);
    final at = _noReminder ? null : (_customAt ?? a.remindAt);
    final item = await s.db.createItem(
      kind: a.kind,
      content: a.title,
      priority: a.priority,
      remindAt: at,
      context: a.context,
      raw: a.raw,
    );
    var suffix = '';
    if (item.remindAt != null) {
      if (!await s.notifications.areEnabled()) {
        suffix = ' · notifications désactivées';
      } else if (await s.notifications.schedule(item) ==
          ScheduleOutcome.inexact) {
        suffix = ' · rappel approximatif';
      }
    }
    widget.controller.clear();
    if (!mounted) return;
    setState(() => _saving = false);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            'Enregistré · ${[_describe(a), if (at != null) formatReminder(at)].join(' · ')}$suffix',
          ),
          persist: false,
          duration: kUndoDuration,
          action: SnackBarAction(
            label: 'Ouvrir',
            onPressed: () => navigator.pushNamed('/item', arguments: item.id),
          ),
        ),
      );
  }

  Future<void> _openFull() async {
    final text = widget.controller.text;
    final saved = await Navigator.of(context)
        .pushNamed('/capture', arguments: CaptureArgs(initialText: text));
    if (saved != null) widget.controller.clear();
  }

  static String _describe(Analysis a) => [a.kind.label, ?a.context].join(' · ');

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final theme = Theme.of(context);
    final speech = AppScope.of(context).speech;
    final hasText = widget.controller.text.trim().isNotEmpty;

    return Material(
      color: p.bg,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListenableBuilder(
              listenable: speech,
              builder: (context, _) {
                if (speech.isListening) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          speech.partialText.isEmpty
                              ? 'J\'écoute…'
                              : speech.partialText,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: p.ink,
                          ),
                        ),
                        const SizedBox(height: 6),
                        LinearProgressIndicator(
                          value: ((speech.level + 2) / 12).clamp(0.05, 1.0),
                          minHeight: 3,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ],
                    ),
                  );
                }
                if (speech.lastError != null) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    child: Text(
                      speech.lastError!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: p.coral,
                      ),
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
            Container(
              decoration: BoxDecoration(
                color: p.field,
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: p.line),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    tooltip: 'Capture détaillée (type, rappel, tags)',
                    onPressed: _openFull,
                    icon: const Icon(Icons.add),
                  ),
                  Expanded(
                    child: TextField(
                      controller: widget.controller,
                      focusNode: widget.focusNode,
                      minLines: 1,
                      maxLines: 5,
                      textCapitalization: TextCapitalization.sentences,
                      keyboardType: TextInputType.multiline,
                      style: theme.textTheme.bodyLarge,
                      decoration: const InputDecoration(
                        hintText: 'Une pensée, en vrac…',
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  MicButton(onText: _onDictated),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(0, 4, 4, 4),
                    child: IconButton.filled(
                      tooltip: 'Enregistrer',
                      onPressed: hasText && !_saving ? _send : null,
                      icon: const Icon(Icons.arrow_upward),
                    ),
                  ),
                ],
              ),
            ),
            if (_preview != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 4, 8, 0),
                child: Row(
                  children: [
                    Icon(
                      Icons.subdirectory_arrow_right,
                      size: 16,
                      color: p.faint,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _describe(_preview!),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: p.muted,
                        ),
                      ),
                    ),
                    // Rappel détecté : touche pour changer date/heure, × pour le retirer.
                    if (_reminder != null)
                      InputChip(
                        visualDensity: VisualDensity.compact,
                        avatar: Icon(Icons.alarm, size: 16, color: p.sage),
                        label: Text(formatReminder(_reminder!)),
                        tooltip: 'Changer la date ou l\'heure',
                        onPressed: _adjustReminder,
                        onDeleted: () => setState(() => _noReminder = true),
                        deleteButtonTooltipMessage: 'Sans rappel',
                      )
                    else
                      ActionChip(
                        visualDensity: VisualDensity.compact,
                        avatar: Icon(Icons.alarm_add, size: 16, color: p.sage),
                        label: const Text('Rappel'),
                        onPressed: _adjustReminder,
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
