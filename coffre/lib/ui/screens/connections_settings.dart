import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../core/reminder_defaults.dart';
import '../../data/app_settings.dart';
import '../../services/notion_import.dart';
import '../../services/notion_service.dart';
import '../../services/secret_store.dart';
import '../../services/system_channel.dart';
import '../theme.dart';

/// Heures utilisées par « demain », « lundi », « ce soir » et les raccourcis.
class DefaultTimesTiles extends StatelessWidget {
  const DefaultTimesTiles({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = AppScope.of(context).settings;
    Future<void> pick(bool morning) async {
      final current = morning
          ? settings.morningMinutes
          : settings.eveningMinutes;
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay(hour: current ~/ 60, minute: current % 60),
        helpText: morning ? 'Heure du matin' : 'Heure du soir',
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        ),
      );
      if (time == null) return;
      final minutes = time.hour * 60 + time.minute;
      morning
          ? await settings.setMorning(minutes)
          : await settings.setEvening(minutes);
    }

    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.wb_twilight),
          title: const Text('Heure du matin'),
          subtitle: Text(
            '${ReminderDefaults.label(ReminderDefaults.morning)} · « demain », « lundi »…',
          ),
          onTap: () => pick(true),
        ),
        ListTile(
          leading: const Icon(Icons.nights_stay_outlined),
          title: const Text('Heure du soir'),
          subtitle: Text(
            '${ReminderDefaults.label(ReminderDefaults.evening)} · « ce soir »',
          ),
          onTap: () => pick(false),
        ),
      ],
    );
  }
}

/// Saisie d'un secret (clé API, jeton), masqué, avec aide.
Future<String?> _askSecret(
  BuildContext context, {
  required String title,
  required String hint,
  required String help,
}) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(help),
          const SizedBox(height: 14),
          TextField(
            controller: controller,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(hintText: hint),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(d, ''),
          child: const Text('Effacer'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(d, controller.text),
          child: const Text('Enregistrer'),
        ),
      ],
    ),
  );
}

void _snack(BuildContext context, String text) => ScaffoldMessenger.of(context)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(text)));

class AiSettingsSection extends StatefulWidget {
  const AiSettingsSection({super.key});

  @override
  State<AiSettingsSection> createState() => _AiSettingsSectionState();
}

class _AiSettingsSectionState extends State<AiSettingsSection> {
  late final AppServices _s = AppScope.of(context);
  final Map<AiProvider, bool> _hasKey = {};
  bool _testing = false;
  bool _started = false;

  static String _keyName(AiProvider provider) => switch (provider) {
    AiProvider.gemini => SecretStore.geminiKey,
    AiProvider.claude => SecretStore.aiKey,
  };

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _refresh();
  }

  Future<void> _refresh() async {
    for (final provider in AiProvider.values) {
      final has = await _s.secrets.has(_keyName(provider));
      if (mounted) setState(() => _hasKey[provider] = has);
    }
  }

  Future<void> _editKey(AiProvider provider) async {
    final value = await _askSecret(
      context,
      title: 'Clé API ${provider.label}',
      hint: provider == AiProvider.gemini ? 'AIza…' : 'sk-ant-…',
      help: switch (provider) {
        AiProvider.gemini =>
          'Gratuit : aistudio.google.com › Get API key › Créer une clé API '
              '(compte Google, sans carte bancaire). Elle reste chiffrée dans le téléphone.',
        AiProvider.claude =>
          'Crée une clé sur console.anthropic.com › API Keys (paiement à l\'usage, '
              'quelques centimes par demande). Elle reste chiffrée dans le téléphone.',
      },
    );
    if (value == null) return;
    await _s.secrets.write(_keyName(provider), value);
    await _refresh();
  }

  Future<void> _test() async {
    setState(() => _testing = true);
    try {
      await _s.ai.ask('Réponds uniquement : OK');
      final name = _s.ai.provider.label;
      if (mounted) _snack(context, '$name répond. L\'assistant est prêt.');
    } catch (e) {
      if (mounted) _snack(context, '$e');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = _s.settings;
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final provider = settings.aiProvider;
        final hasKey = _hasKey[provider];
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: SizedBox(
                width: double.infinity,
                child: SegmentedButton<AiProvider>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: AiProvider.gemini,
                      label: Text('Gemini (gratuit)'),
                    ),
                    ButtonSegment(
                      value: AiProvider.claude,
                      label: Text('Claude (payant)'),
                    ),
                  ],
                  selected: {provider},
                  onSelectionChanged: (v) => settings.setAiProvider(v.first),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.key_outlined),
              title: Text('Clé API ${provider.label}'),
              subtitle: Text(
                hasKey == null ? '…' : (hasKey ? 'Configurée' : 'À ajouter'),
              ),
              onTap: () => _editKey(provider),
              trailing: hasKey == true
                  ? (_testing
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : TextButton(
                            onPressed: _test,
                            child: const Text('Tester'),
                          ))
                  : null,
            ),
            SwitchListTile(
              secondary: const Icon(Icons.shield_outlined),
              title: const Text('Masquer les données personnelles'),
              subtitle: const Text(
                'Noms avec civilité (Mme Dupont), n° national, téléphone, e-mail, IBAN : '
                'remplacés avant l\'envoi, remis dans la réponse.',
              ),
              value: settings.aiMask,
              onChanged: settings.setAiMask,
            ),
            _Note(switch (provider) {
              AiProvider.gemini =>
                'Gemini Flash (Google), offre gratuite avec limites par minute et par jour. '
                    'Google peut conserver et relire les textes de l\'offre gratuite : garde le '
                    'masquage activé, pas de détail sensible sur un bénéficiaire.',
              AiProvider.claude =>
                'Claude Opus 5 (Anthropic), payant à l\'usage. Rien n\'est envoyé sans ton '
                    'geste. Secret professionnel : pas de détail sensible sur un bénéficiaire.',
            }),
          ],
        );
      },
    );
  }
}

class AgendaSettingsSection extends StatelessWidget {
  const AgendaSettingsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final settings = s.settings;

    Future<void> enable(bool on) async {
      if (!on) return settings.setAgendaEnabled(false);
      if (!await s.system.requestCalendarPermission()) {
        if (context.mounted) {
          _snack(
            context,
            'Accès à l\'agenda refusé. Réglages Android › Applications › Coffre › Autorisations.',
          );
        }
        return;
      }
      await settings.setAgendaEnabled(true);
      if (settings.agendaCalendarId == null) {
        // Par défaut : l'agenda principal du compte Google.
        final calendars = (await s.system.listCalendars())
            .where((c) => c.writable)
            .toList();
        final best =
            calendars
                .where((c) => c.isGoogle && c.name == c.account)
                .firstOrNull ??
            calendars.where((c) => c.isGoogle).firstOrNull ??
            calendars.firstOrNull;
        if (best != null) {
          await settings.setAgendaCalendar(
            best.id,
            '${best.name} (${best.account})',
          );
        }
      }
    }

    Future<void> choose() async {
      if (!await s.system.requestCalendarPermission()) return;
      final calendars = (await s.system.listCalendars())
          .where((c) => c.writable)
          .toList();
      if (!context.mounted) return;
      final chosen = await showDialog<PhoneCalendar>(
        context: context,
        builder: (d) => SimpleDialog(
          title: const Text('Agenda pour les nouveaux événements'),
          children: [
            if (calendars.isEmpty)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  'Aucun agenda modifiable. Ajoute ton compte Google dans Samsung Agenda.',
                ),
              ),
            for (final c in calendars)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(d, c),
                child: Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: Color(c.color),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text('${c.name}\n${c.account}')),
                  ],
                ),
              ),
          ],
        ),
      );
      if (chosen != null) {
        await settings.setAgendaCalendar(
          chosen.id,
          '${chosen.name} (${chosen.account})',
        );
      }
    }

    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => Column(
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.event_outlined),
            title: const Text('Afficher mon agenda dans Jour'),
            subtitle: const Text('Rendez-vous d\'aujourd\'hui et de demain'),
            value: settings.agendaEnabled,
            onChanged: enable,
          ),
          ListTile(
            leading: const Icon(Icons.edit_calendar_outlined),
            title: const Text('Agenda pour « Ajouter à l\'agenda »'),
            subtitle: Text(settings.agendaCalendarName ?? 'À choisir'),
            onTap: choose,
          ),
          const _Note(
            'Coffre lit et écrit dans l\'agenda du téléphone, déjà synchronisé avec ton compte Google : '
            'aucune connexion Google dans l\'app.',
          ),
        ],
      ),
    );
  }
}

class NotionSettingsSection extends StatefulWidget {
  const NotionSettingsSection({super.key});

  @override
  State<NotionSettingsSection> createState() => _NotionSettingsSectionState();
}

class _NotionSettingsSectionState extends State<NotionSettingsSection> {
  late final AppServices _s = AppScope.of(context);
  bool? _hasToken;
  bool _loading = false;
  bool _importing = false;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _refresh();
  }

  Future<void> _refresh() async {
    final has = await _s.secrets.has(SecretStore.notionKey);
    if (mounted) setState(() => _hasToken = has);
  }

  Future<void> _editToken() async {
    final value = await _askSecret(
      context,
      title: 'Jeton Notion',
      hint: 'ntn_…',
      help:
          '1. notion.so/profile/integrations › Nouvelle intégration (interne) › copie le jeton.\n'
          '2. Dans Notion, ouvre ta base › ••• › Connexions › ajoute l\'intégration.\n'
          '3. Colle le jeton ici, puis choisis la base.',
    );
    if (value == null) return;
    await _s.secrets.write(SecretStore.notionKey, value);
    if (value.trim().isEmpty) await _s.settings.setNotionTarget(null);
    await _refresh();
  }

  /// Liste des bases partagées avec l'intégration ; null si annulé.
  Future<NotionTarget?> _pickBase(String title) async {
    setState(() => _loading = true);
    List<NotionTarget> targets;
    try {
      targets = await _s.notion.listTargets();
    } catch (e) {
      if (mounted) _snack(context, '$e');
      return null;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    if (!mounted) return null;
    return showDialog<NotionTarget>(
      context: context,
      builder: (d) => SimpleDialog(
        title: Text(title),
        children: [
          if (targets.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'Aucune base visible. Partage une base avec ton intégration (••• › Connexions).',
              ),
            ),
          for (final t in targets)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(d, t),
              child: Text(
                t.dateProp == null ? t.name : '${t.name}\ndate : ${t.dateProp}',
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _chooseTarget() async {
    final chosen = await _pickBase('Base où envoyer');
    if (chosen != null) await _s.settings.setNotionTarget(chosen.toMap());
  }

  Future<void> _chooseImport() async {
    final chosen = await _pickBase('Base à importer (Grokbot…)');
    if (chosen == null) return;
    await _s.settings.setNotionImport(chosen.toMap(), null);
    await _import(chosen);
  }

  Future<void> _import(NotionTarget target) async {
    setState(() => _importing = true);
    try {
      final result = await importNotionTasks(
        _s.db,
        _s.notion,
        target,
        context: _s.settings.notionImportContext,
      );
      for (final item in [...result.added, ...result.closed]) {
        await _s.notifications.schedule(item);
      }
      String plural(int n, String word) => '$n $word${n > 1 ? 's' : ''}';
      final n = result.added.length;
      final details = [
        if (result.existing > 0) '${result.existing} déjà dans Coffre',
        if (result.closed.isNotEmpty)
          '${plural(result.closed.length, 'fermée')} (Fait dans Notion)',
        if (result.done > 0)
          '${plural(result.done, 'terminée')} ignorée${result.done > 1 ? 's' : ''}',
      ];
      if (mounted) {
        _snack(
          context,
          '${n == 0 ? 'Aucune nouvelle tâche' : '${plural(n, 'tâche')} importée${n > 1 ? 's' : ''} dans l\'Inbox'}'
          '${details.isEmpty ? '' : ' · ${details.join(' · ')}'}',
        );
      }
    } catch (e) {
      if (mounted) _snack(context, '$e');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = _s.settings;
    Widget spinner(bool on) => on
        ? const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const SizedBox.shrink();
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final ready = _hasToken == true;
        final target = NotionTarget.fromMap(settings.notionTarget);
        final source = NotionTarget.fromMap(settings.notionImport);
        return Column(
          children: [
            ListTile(
              leading: const Icon(Icons.vpn_key_outlined),
              title: const Text('Jeton d\'intégration'),
              subtitle: Text(
                _hasToken == null ? '…' : (ready ? 'Configuré' : 'À ajouter'),
              ),
              onTap: _editToken,
            ),
            ListTile(
              enabled: ready,
              leading: const Icon(Icons.upload_outlined),
              title: const Text('Base où envoyer'),
              subtitle: Text(target?.name ?? 'À choisir'),
              trailing: spinner(_loading),
              onTap: ready ? _chooseTarget : null,
            ),
            ListTile(
              enabled: ready,
              leading: const Icon(Icons.download_outlined),
              title: const Text('Base à importer (Grokbot…)'),
              subtitle: Text(source == null ? 'À choisir' : source.name),
              onTap: ready ? _chooseImport : null,
            ),
            SwitchListTile(
              secondary: const Icon(Icons.sync),
              title: const Text('Importer à chaque ouverture'),
              subtitle: const Text(
                'Les nouvelles tâches arrivent dans l\'Inbox',
              ),
              value: settings.notionAutoImport,
              onChanged: ready && source != null
                  ? settings.setNotionAutoImport
                  : null,
            ),
            ListTile(
              enabled: ready && source != null && !_importing,
              leading: const Icon(Icons.refresh),
              title: const Text('Importer maintenant'),
              trailing: spinner(_importing),
              onTap: ready && source != null ? () => _import(source) : null,
            ),
            SwitchListTile(
              secondary: const Icon(Icons.task_alt),
              title: const Text('« Fait » dans Coffre → Fait dans Notion'),
              subtitle: const Text(
                'Pour les éléments venus de Notion ou envoyés vers Notion',
              ),
              value: settings.notionSyncDone,
              onChanged: ready ? settings.setNotionSyncDone : null,
            ),
            const _Note(
              'Import : titre, notes et contenu de la page, échéance → rappel, P1/P2/P3 → priorité, '
              'listes (Contexte, Domaine…) → tags, statuts Bloqué / Délégué → tags. '
              'Une tâche passée à « Fait » dans Notion se ferme aussi dans Coffre.',
            ),
          ],
        );
      },
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
    child: Text(
      text,
      style: Theme.of(context).textTheme.bodyMedium
          ?.copyWith(color: Palette.of(context).muted),
    ),
  );
}
