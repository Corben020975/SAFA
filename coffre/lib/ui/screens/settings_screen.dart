import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../core/date_labels.dart';
import '../../services/notification_service.dart';
import 'connections_settings.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final settings = s.settings;

    return Scaffold(
      appBar: AppBar(title: const Text('Réglages')),
      body: ListenableBuilder(
        listenable: settings,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            const _Header('Apparence'),
            _Labeled(
              label: 'Thème',
              child: SegmentedButton<ThemeMode>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: ThemeMode.dark, label: Text('Sombre')),
                  ButtonSegment(value: ThemeMode.light, label: Text('Clair')),
                  ButtonSegment(
                    value: ThemeMode.system,
                    label: Text('Système'),
                  ),
                ],
                selected: {settings.themeMode},
                onSelectionChanged: (v) => settings.setThemeMode(v.first),
              ),
            ),
            _Labeled(
              label: 'Taille du texte (en plus du réglage Samsung)',
              child: SegmentedButton<double>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 1.0, label: Text('Normale')),
                  ButtonSegment(value: 1.15, label: Text('Grande')),
                  ButtonSegment(value: 1.3, label: Text('Très grande')),
                ],
                selected: {settings.textScale},
                onSelectionChanged: (v) => settings.setTextScale(v.first),
              ),
            ),
            const _Header('Dictée'),
            _Labeled(
              label: 'Langue',
              child: SegmentedButton<String>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 'fr_BE', label: Text('Français (BE)')),
                  ButtonSegment(value: 'fr_FR', label: Text('Français (FR)')),
                ],
                selected: {settings.dictationLocale},
                onSelectionChanged: (v) => settings.setDictationLocale(v.first),
              ),
            ),
            SwitchListTile(
              title: const Text('Reconnaissance sur l\'appareil uniquement'),
              subtitle: const Text(
                'Aucun son envoyé en ligne. Nécessite le pack « Français » '
                'hors-ligne du moteur vocal (Google ou Samsung).',
              ),
              value: settings.onDeviceDictation,
              onChanged: settings.setOnDeviceDictation,
            ),
            const _Header('Rappels'),
            ListTile(
              leading: const Icon(Icons.verified_outlined),
              title: const Text('Vérifier la fiabilité des rappels'),
              subtitle: const Text('Notifications, alarmes, batterie Samsung'),
              onTap: () => Navigator.of(context).pushNamed('/onboarding'),
            ),
            ListTile(
              leading: const Icon(Icons.notifications_active_outlined),
              title: const Text('Notification de test dans 1 minute'),
              onTap: () async {
                final outcome = await s.notifications.scheduleTest(
                  const Duration(minutes: 1),
                );
                if (!context.mounted) return;
                _snack(
                  context,
                  outcome == ScheduleOutcome.exact
                      ? 'Test prévu dans 1 minute.'
                      : 'Test prévu (approximatif : autorise « Alarmes et rappels »).',
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.tune),
              title: const Text('Son et vibration des rappels'),
              subtitle: const Text('Réglages Android du canal « Rappels »'),
              onTap: s.system.openNotificationSettings,
            ),
            const DefaultTimesTiles(),
            const _Header('Assistant IA'),
            const AiSettingsSection(),
            const _Header('Agenda Google'),
            const AgendaSettingsSection(),
            const _Header('Notion'),
            const NotionSettingsSection(),
            const _Header('Sauvegarde'),
            ListTile(
              leading: const Icon(Icons.save_alt),
              title: const Text('Exporter une sauvegarde (JSON)'),
              subtitle: Text(
                settings.lastExportAt == null
                    ? 'Jamais exporté'
                    : 'Dernier export : ${formatReminder(settings.lastExportAt!)}',
              ),
              onTap: () => _export(context, json: true),
            ),
            ListTile(
              leading: const Icon(Icons.table_chart_outlined),
              title: const Text('Exporter en tableau (CSV, Excel)'),
              onTap: () => _export(context, json: false),
            ),
            ListTile(
              leading: const Icon(Icons.restore),
              title: const Text('Restaurer une sauvegarde (JSON)'),
              subtitle: const Text('Ajoute les éléments absents, sans doublon'),
              onTap: () => _import(context),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Text(
                'Les fichiers exportés ne sont pas chiffrés : range-les dans un '
                'endroit sûr (dossier personnel, clé USB).',
              ),
            ),
            const _Header('Confidentialité'),
            ListTile(
              leading: Icon(s.encryptionActive ? Icons.lock : Icons.lock_open),
              title: const Text('Chiffrement de la base'),
              subtitle: Text(
                s.encryptionActive
                    ? 'Actif (ChaCha20). Clé unique stockée dans le Keystore Android.'
                    : 'Inactif : la bibliothèque de chiffrement n\'est pas chargée.',
              ),
            ),
            const ListTile(
              leading: Icon(Icons.wifi_tethering_off),
              title: Text('Internet seulement à ta demande'),
              subtitle: Text(
                'Utilisé uniquement quand tu lances l\'assistant IA (Anthropic) '
                'ou un envoi / une recherche Notion. Aucun compte Coffre, aucune statistique.',
              ),
            ),
            FutureBuilder<String>(
              future: s.system.appVersion(),
              builder: (context, snap) => ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('Version'),
                subtitle: Text(snap.data ?? '…'),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.gavel_outlined),
              title: const Text('Licences open source'),
              onTap: () =>
                  showLicensePage(context: context, applicationName: 'Coffre'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _export(BuildContext context, {required bool json}) async {
    final s = AppScope.of(context);
    try {
      final saved = json
          ? await s.backup.exportJson()
          : await s.backup.exportCsv();
      if (saved && json) await s.settings.markExported();
      if (context.mounted && saved) _snack(context, 'Fichier enregistré.');
    } catch (e) {
      if (context.mounted) _snack(context, 'Échec de l\'export : $e');
    }
  }

  Future<void> _import(BuildContext context) async {
    final s = AppScope.of(context);
    try {
      final report = await s.backup.importJson();
      if (report == null || !context.mounted) return;
      _snack(
        context,
        '${report.added} élément(s) restauré(s), ${report.skipped} déjà présent(s).',
      );
    } on FormatException catch (e) {
      if (context.mounted) _snack(context, e.message);
    } catch (e) {
      if (context.mounted) _snack(context, 'Fichier illisible : $e');
    }
  }

  static void _snack(BuildContext context, String text) =>
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(text)));
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleSmall
          ?.copyWith(color: Theme.of(context).colorScheme.primary),
    ),
  );
}

class _Labeled extends StatelessWidget {
  const _Labeled({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label),
        const SizedBox(height: 8),
        SizedBox(width: double.infinity, child: child),
      ],
    ),
  );
}
