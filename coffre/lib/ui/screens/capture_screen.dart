import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../core/date_labels.dart';
import '../../data/enums.dart';
import '../../services/notification_service.dart';
import '../../services/reminder_parser.dart';
import '../widgets/dictation_button.dart';
import '../widgets/reminder_field.dart';
import '../widgets/selectors.dart';
import '../widgets/tags_editor.dart';

class CaptureArgs {
  const CaptureArgs({this.kind, this.startWithVoice = false});
  final ItemKind? kind;
  final bool startWithVoice;
}

class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key, this.args = const CaptureArgs()});
  final CaptureArgs args;

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  late final AppServices _s = AppScope.of(context);
  final _text = TextEditingController();
  final _focus = FocusNode();

  late ItemKind _kind = widget.args.kind ?? _s.settings.lastKind;
  ItemPriority _priority = ItemPriority.normal;
  List<String> _tags = [];
  DateTime? _remindAt;
  ParsedReminder? _suggestion;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _text.addListener(_onTextChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.args.startWithVoice) {
        MicButton.toggle(context, _onDictated);
      } else {
        _focus.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    if (_s.speech.isListening) _s.speech.stop();
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final suggestion = _remindAt == null ? ReminderParser.parse(_text.text) : null;
    if (suggestion?.when != _suggestion?.when || _text.text.isEmpty) {
      setState(() => _suggestion = suggestion);
    } else {
      setState(() {}); // état du bouton Enregistrer
    }
  }

  void _onDictated(String dictated) {
    // Le moteur peut livrer le résultat final après la fermeture de l'écran.
    if (!mounted) return;
    final updated = appendDictation(_text.text, dictated);
    _text.value = TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(offset: updated.length),
    );
  }

  void _applySuggestion() {
    final s = _suggestion;
    if (s == null) return;
    final cleaned = ReminderParser.strip(_text.text, s);
    setState(() {
      _remindAt = s.when;
      _suggestion = null;
    });
    _text.value = TextEditingValue(
      text: cleaned,
      selection: TextSelection.collapsed(offset: cleaned.length),
    );
  }

  Future<void> _save() async {
    final content = _text.text.trim();
    if (content.isEmpty || _saving) return;
    setState(() => _saving = true);
    if (_s.speech.isListening) await _s.speech.stop();

    final item = await _s.db.createItem(
      kind: _kind,
      content: content,
      priority: _priority,
      tags: _tags,
      remindAt: _remindAt,
    );
    await _s.settings.setLastKind(_kind);

    var message = '${_kind.label} ajoutée à l\'Inbox';
    SnackBarAction? action;
    if (item.remindAt != null) {
      if (!await _s.notifications.areEnabled()) {
        message = 'Enregistré, mais les notifications sont désactivées';
        action = SnackBarAction(
          label: 'Corriger',
          onPressed: () => _s.system.openNotificationSettings(),
        );
      } else {
        final outcome = await _s.notifications.schedule(item);
        message = 'Rappel : ${formatReminder(item.remindAt!)}';
        if (outcome == ScheduleOutcome.inexact) {
          message += ' (approximatif : autorise « Alarmes et rappels »)';
        }
      }
    }
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop(item);
    messenger.showSnackBar(SnackBar(content: Text(message), action: action));
  }

  Future<void> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Abandonner cette capture ?'),
        content: const Text('Le texte saisi sera perdu.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Continuer'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Abandonner'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasText = _text.text.trim().isNotEmpty;

    return PopScope(
      canPop: !hasText,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmDiscard();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Fermer',
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.maybePop(context),
          ),
          title: const Text('Nouvelle capture'),
        ),
        body: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                children: [
                  KindSelector(
                    value: _kind,
                    onChanged: (k) => setState(() => _kind = k),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _text,
                    focusNode: _focus,
                    minLines: 4,
                    maxLines: null,
                    keyboardType: TextInputType.multiline,
                    textCapitalization: TextCapitalization.sentences,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontSize: 19),
                    decoration: const InputDecoration(
                      hintText: 'Qu\'as-tu en tête ?\nEx. : « Appeler le médecin demain 9h »',
                    ),
                  ),
                  const SizedBox(height: 8),
                  const DictationPanel(),
                  if (_suggestion != null && _remindAt == null)
                    Card(
                      color: scheme.tertiaryContainer,
                      child: ListTile(
                        leading: Icon(Icons.auto_awesome, color: scheme.onTertiaryContainer),
                        title: Text(
                          'Rappel détecté : ${formatReminder(_suggestion!.when)}',
                          style: TextStyle(color: scheme.onTertiaryContainer),
                        ),
                        subtitle: Text(
                          'Programmer et retirer la date du texte',
                          style: TextStyle(color: scheme.onTertiaryContainer),
                        ),
                        trailing: FilledButton(
                          onPressed: _applySuggestion,
                          child: const Text('Appliquer'),
                        ),
                        onTap: _applySuggestion,
                      ),
                    ),
                  const SectionLabel('Rappel'),
                  ReminderField(
                    value: _remindAt,
                    onChanged: (d) => setState(() {
                      _remindAt = d;
                      if (d == null) _suggestion = ReminderParser.parse(_text.text);
                    }),
                  ),
                  const SectionLabel('Priorité'),
                  PrioritySelector(
                    value: _priority,
                    onChanged: (p) => setState(() => _priority = p),
                  ),
                  const SectionLabel('Tags'),
                  TagsEditor(
                    tags: _tags,
                    onChanged: (t) => setState(() => _tags = t),
                  ),
                ],
              ),
            ),
            // Reste collé au-dessus du clavier : enregistrement au pouce.
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  children: [
                    MicButton(onText: _onDictated, large: true),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: hasText && !_saving ? _save : null,
                        icon: const Icon(Icons.check),
                        label: const Text('Enregistrer'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
