import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'core/app_services.dart';
import 'core/date_labels.dart';
import 'data/app_settings.dart';
import 'data/backup_service.dart';
import 'data/db_opener.dart';
import 'data/enums.dart';
import 'services/ai/ai_assistant.dart';
import 'services/ai/claude_client.dart';
import 'services/ai/gemini_client.dart';
import 'services/capture_analyzer.dart';
import 'services/notification_service.dart';
import 'services/notion_service.dart';
import 'services/secret_store.dart';
import 'services/speech_service.dart';
import 'services/system_channel.dart';
import 'ui/theme.dart';
import 'ui/widgets/ai_sheet.dart';
import 'ui/widgets/reminder_field.dart';

/// « Ajouter à Coffre » : petit panneau posé par-dessus l'app d'origine
/// (Outlook, WhatsApp…). On enregistre et on reste dans le mail.
Future<void> runQuickCapture() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('fr');
  Intl.defaultLocale = 'fr';
  const channel = MethodChannel('coffre/quick');
  final shared =
      await channel.invokeMapMethod<String, Object?>('shared') ?? const {};
  final text = '${shared['text'] ?? ''}'.trim();
  final source = shared['source'] as String?;

  final db = await openDatabaseForBackground();
  if (db == null) {
    // Coffre n'a jamais été ouvert : la clé de la base n'existe pas encore.
    runApp(
      const _QuickMessage('Ouvre Coffre une première fois, puis réessaie.'),
    );
    return;
  }
  final settings = AppSettings(db);
  await settings.load();
  final notifications = NotificationService();
  await notifications.init();
  final system = SystemChannel();
  final secrets = SecretStore();
  final services = AppServices(
    db: db,
    settings: settings,
    notifications: notifications,
    speech: SpeechService(),
    system: system,
    backup: BackupService(db, system, notifications),
    secrets: secrets,
    ai: AiAssistant(
      ClaudeClient(() => secrets.read(SecretStore.aiKey)),
      GeminiClient(() => secrets.read(SecretStore.geminiKey)),
      settings,
    ),
    notion: NotionService(() => secrets.read(SecretStore.notionKey)),
    encryptionActive: true,
  );
  runApp(
    AppScope(
      services: services,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        color: Colors.transparent,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: settings.themeMode,
        locale: const Locale('fr', 'BE'),
        supportedLocales: const [Locale('fr', 'BE'), Locale('fr')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: QuickCaptureSheet(text: text, source: source, channel: channel),
      ),
    ),
  );
}

class QuickCaptureSheet extends StatefulWidget {
  const QuickCaptureSheet({
    super.key,
    required this.text,
    required this.source,
    required this.channel,
  });
  final String text;
  final String? source;
  final MethodChannel channel;

  @override
  State<QuickCaptureSheet> createState() => _QuickCaptureSheetState();
}

class _QuickCaptureSheetState extends State<QuickCaptureSheet> {
  late final _field = TextEditingController(text: widget.text);
  late Analysis _analysis = CaptureAnalyzer.analyze(widget.text);
  DateTime? _customAt;
  bool _noReminder = false;
  bool _hasAiKey = false;
  bool _thinking = false;
  bool _saved = false;

  DateTime? get _reminder =>
      _noReminder ? null : (_customAt ?? _analysis.remindAt);

  @override
  void initState() {
    super.initState();
    _field.addListener(() {
      if (_field.text.trim().isEmpty) return;
      setState(() => _analysis = CaptureAnalyzer.analyze(_field.text));
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = AppScope.of(context);
    final key = s.settings.aiProvider == AiProvider.gemini
        ? SecretStore.geminiKey
        : SecretStore.aiKey;
    s.secrets.has(key).then((has) {
      if (mounted && has != _hasAiKey) setState(() => _hasAiKey = has);
    });
  }

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  Future<void> _close() => widget.channel.invokeMethod<void>('close');

  Future<void> _rewrite() async {
    if (!await ensureAiReady(context) || !mounted) return;
    final ai = AppScope.of(context).ai;
    setState(() => _thinking = true);
    try {
      final line = await ai.toTask(widget.text);
      if (!mounted) return;
      _field.text = line;
      _customAt = null;
      _noReminder = false;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _thinking = false);
    }
  }

  Future<void> _adjustReminder() async {
    final chosen = await pickReminderDateTime(context, _reminder);
    if (chosen != null && mounted) {
      setState(() {
        _customAt = chosen;
        _noReminder = false;
      });
    }
  }

  Future<void> _openFull() async {
    final uri = Uri(
      scheme: 'coffre',
      host: 'capture',
      queryParameters: {'text': _field.text.trim()},
    );
    await widget.channel.invokeMethod<void>('openFull', {'uri': '$uri'});
  }

  Future<void> _save() async {
    final text = _field.text.trim();
    if (text.isEmpty || _saved) return;
    final s = AppScope.of(context);
    final a = CaptureAnalyzer.analyze(text);
    final at = _reminder;
    final item = await s.db.createItem(
      kind: a.kind,
      content: a.title,
      priority: a.priority,
      tags: [?widget.source],
      remindAt: at,
      recurrence: at == null ? Recurrence.none : a.recurrence,
      context: a.context,
      raw: widget.text == a.title ? null : widget.text,
    );
    await s.notifications.schedule(item);
    if (!mounted) return;
    setState(() => _saved = true);
    await Future<void>.delayed(const Duration(milliseconds: 700));
    await _close();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final theme = Theme.of(context);
    final at = _reminder;
    final details = [
      _analysis.kind.label,
      if (_analysis.priority != ItemPriority.normal) _analysis.priority.label,
      ?_analysis.context,
      if (widget.source != null) '#${widget.source}',
    ].join(' · ');

    return Scaffold(
      backgroundColor: Colors.black54,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _close,
        child: SafeArea(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: GestureDetector(
              onTap: () {}, // un tap dans le panneau ne le ferme pas
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
                decoration: BoxDecoration(
                  color: p.card,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: p.line),
                ),
                child: _saved
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.check_circle, color: p.sage),
                            const SizedBox(width: 10),
                            Flexible(
                              child: Text(
                                at == null
                                    ? 'Enregistré dans Coffre'
                                    : 'Enregistré · ${formatReminder(at)}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium,
                              ),
                            ),
                          ],
                        ),
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.inventory_2_outlined,
                                size: 18,
                                color: p.sage,
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  'Ajouter à Coffre',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: displayStyle(context, 20),
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (_hasAiKey)
                                _thinking
                                    ? const Padding(
                                        padding: EdgeInsets.all(12),
                                        child: SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        ),
                                      )
                                    : TextButton.icon(
                                        onPressed: _rewrite,
                                        icon: const Icon(
                                          Icons.auto_awesome,
                                          size: 18,
                                        ),
                                        label: const Text('Reformuler'),
                                      ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _field,
                            minLines: 1,
                            maxLines: 6,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: const InputDecoration(
                              hintText: 'Tâche, idée, note…',
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            details,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: p.muted,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            children: [
                              if (at != null)
                                InputChip(
                                  avatar: Icon(
                                    Icons.alarm,
                                    size: 16,
                                    color: p.sage,
                                  ),
                                  label: Text(
                                    _analysis.recurrence == Recurrence.none
                                        ? formatReminder(at)
                                        : '${formatReminder(at)} · ${_analysis.recurrence.short}',
                                  ),
                                  onPressed: _adjustReminder,
                                  onDeleted: () =>
                                      setState(() => _noReminder = true),
                                  deleteButtonTooltipMessage: 'Sans rappel',
                                )
                              else
                                ActionChip(
                                  avatar: Icon(
                                    Icons.alarm_add,
                                    size: 16,
                                    color: p.sage,
                                  ),
                                  label: const Text('Rappel'),
                                  onPressed: _adjustReminder,
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          // Wrap : passe à la ligne si l'écran est étroit.
                          Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 8,
                            children: [
                              TextButton(
                                onPressed: _openFull,
                                child: const Text('Ouvrir dans Coffre'),
                              ),
                              FilledButton(
                                onPressed: _save,
                                child: const Text('Enregistrer'),
                              ),
                            ],
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickMessage extends StatelessWidget {
  const _QuickMessage(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark(useMaterial3: true),
    home: Scaffold(
      backgroundColor: Colors.black54,
      body: GestureDetector(
        onTap: () =>
            const MethodChannel('coffre/quick').invokeMethod<void>('close'),
        child: Center(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(text),
            ),
          ),
        ),
      ),
    ),
  );
}
