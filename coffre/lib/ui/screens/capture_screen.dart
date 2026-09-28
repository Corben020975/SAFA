import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../core/date_labels.dart';
import '../../data/enums.dart';
import '../../services/capture_analyzer.dart';
import '../../services/notification_service.dart';
import '../../services/reminder_parser.dart';
import '../theme.dart';
import '../widgets/dictation_button.dart';
import '../widgets/reminder_field.dart';
import '../widgets/selectors.dart';
import '../widgets/tags_editor.dart';

class CaptureArgs {
  const CaptureArgs({
    this.kind,
    this.startWithVoice = false,
    this.initialText = '',
  });
  final ItemKind? kind;
  final bool startWithVoice;

  /// Texte repris de la barre de capture.
  final String initialText;
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
  String? _context;
  List<String> _tags = [];
  DateTime? _remindAt;
  bool _preAlert = false;
  ParsedReminder? _suggestion;
  bool _saving = false;

  /// Texte d'origine, conservé si « Appliquer » a nettoyé la saisie.
  String? _raw;

  // Tant que tu n'y touches pas, type, priorité et contexte suivent l'analyse.
  late bool _kindTouched = widget.args.kind != null;
  bool _priorityTouched = false;
  bool _contextTouched = false;

  @override
  void initState() {
    super.initState();
    _text.text = widget.args.initialText;
    _text.addListener(_onTextChanged);
    if (_text.text.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _onTextChanged());
    }
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
    final text = _text.text.trim();
    final a = text.isEmpty ? null : CaptureAnalyzer.analyze(text);
    setState(() {
      _suggestion = _remindAt == null && text.isNotEmpty
          ? ReminderParser.parse(text)
          : null;
      if (a == null) return;
      if (!_kindTouched) _kind = a.kind;
      if (!_priorityTouched) _priority = a.priority;
      if (!_contextTouched) _context = a.context;
    });
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
    final original = _text.text.trim();
    final a = CaptureAnalyzer.analyze(original);
    final cleaned = a.title;
    setState(() {
      _remindAt = s.when;
      _suggestion = null;
      _raw ??= original;
      // Le texte nettoyé ne doit pas relancer une autre lecture : on fige.
      if (!_kindTouched) _kind = a.kind;
      if (!_priorityTouched) _priority = a.priority;
      if (!_contextTouched) _context = a.context;
      _kindTouched = _priorityTouched = _contextTouched = true;
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
      context: _context,
      preAlert: _remindAt != null && _preAlert,
      raw: _raw != null && _raw != content ? _raw : null,
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
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        action: action,
        persist: false,
        duration: kUndoDuration,
      ),
    );
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
                    onChanged: (k) => setState(() {
                      _kind = k;
                      _kindTouched = true;
                    }),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _text,
                    focusNode: _focus,
                    minLines: 4,
                    maxLines: null,
                    keyboardType: TextInputType.multiline,
                    textCapitalization: TextCapitalization.sentences,
                    style: Theme.of(context).textTheme.bodyLarge
                        ?.copyWith(fontSize: 19),
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
                        leading: Icon(
                          Icons.auto_awesome,
                          color: scheme.onTertiaryContainer,
                        ),
                        title: Text(
                          'Rappel détecté : ${formatReminder(_suggestion!.when)}',
                          style: TextStyle(color: scheme.onTertiaryContainer),
                        ),
                        subtitle: Text(
                          'Programmer et nettoyer le texte (l\'original est gardé)',
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
                      if (d == null) {
                        _suggestion = ReminderParser.parse(_text.text);
                      }
                    }),
                  ),
                  if (_remindAt != null)
                    PreAlertSwitch(
                      value: _preAlert,
                      onChanged: (v) => setState(() => _preAlert = v),
                    ),
                  const SectionLabel('Priorité'),
                  PrioritySelector(
                    value: _priority,
                    onChanged: (p) => setState(() {
                      _priority = p;
                      _priorityTouched = true;
                    }),
                  ),
                  const SectionLabel('Contexte'),
                  ContextSelector(
                    value: _context,
                    onChanged: (c) => setState(() {
                      _context = c;
                      _contextTouched = true;
                    }),
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
