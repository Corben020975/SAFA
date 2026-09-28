import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../services/notification_service.dart';

/// Assistant « Rappels fiables » : premier lancement, puis accessible
/// depuis Réglages. Les statuts se rafraîchissent au retour des réglages système.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  late final AppServices _s = AppScope.of(context);
  late final AppLifecycleListener _lifecycle;
  bool? _notifications, _exact, _battery, _mic;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _refresh);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _refresh();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final n = await _s.notifications.areEnabled();
    final e = await _s.notifications.canScheduleExact();
    final b = await _s.system.isIgnoringBatteryOptimizations();
    final m = await _s.speech.hasPermission;
    if (!mounted) return;
    setState(() {
      _notifications = n;
      _exact = e;
      _battery = b;
      _mic = m;
    });
  }

  Future<void> _askNotifications() async {
    final granted = await _s.notifications.requestPermission();
    // Refus définitif : Android ne réaffiche plus la question, il faut
    // passer par les réglages.
    if (!granted) await _s.system.openNotificationSettings();
    await _refresh();
  }

  Future<void> _test() async {
    final outcome = await _s.notifications.scheduleTest(
      const Duration(minutes: 1),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 6),
        content: Text(
          outcome == ScheduleOutcome.exact
              ? 'Test prévu dans 1 minute. Ferme l\'app (balaye-la des apps récentes) et verrouille l\'écran.'
              : 'Test prévu, mais en mode approximatif : autorise « Alarmes et rappels ».',
        ),
      ),
    );
  }

  Future<void> _finish() async {
    await _s.settings.setOnboardingDone(true);
    if (!mounted) return;
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      navigator.pushReplacementNamed('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rappels fiables')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text(
            'One UI met les apps en veille pour économiser la batterie. '
            'Ces réglages garantissent que tes rappels sonnent à l\'heure, '
            'même app fermée ou téléphone verrouillé.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 16),
          _StepCard(
            number: 1,
            title: 'Notifications',
            why: 'Pour afficher les rappels.',
            ok: _notifications,
            actionLabel: 'Autoriser',
            onAction: _askNotifications,
          ),
          _StepCard(
            number: 2,
            title: 'Alarmes et rappels',
            why: 'Pour déclencher à la minute près, même en veille profonde.',
            ok: _exact,
            actionLabel: 'Autoriser',
            onAction: () async {
              await _s.notifications.requestExactAlarms();
              await _refresh();
            },
          ),
          _StepCard(
            number: 3,
            title: 'Batterie : non restreinte',
            why: 'Pour empêcher One UI d\'endormir Coffre.',
            ok: _battery,
            actionLabel: 'Autoriser',
            onAction: _s.system.requestIgnoreBatteryOptimizations,
            secondaryLabel: 'Ouvrir Infos sur l\'appli',
            onSecondary: _s.system.openAppSettings,
            help:
                'Si besoin, à la main :\n'
                '• Paramètres › Applications › Coffre › Batterie › Non restreinte\n'
                '• Paramètres › Batterie › Limites d\'utilisation en arrière-plan › '
                'Applications jamais en veille › + Coffre\n'
                '• Dans ce même écran, vérifie que Coffre n\'est pas dans '
                '« Applications en veille profonde ».',
          ),
          _StepCard(
            number: 4,
            title: 'Micro (facultatif)',
            why: 'Pour dicter. Sans lui, le clavier reste disponible.',
            ok: _mic,
            actionLabel: 'Autoriser',
            onAction: () async {
              await _s.speech.ensureReady();
              await _refresh();
            },
          ),
          _StepCard(
            number: 5,
            title: 'Tester',
            why: 'Une notification de test dans 1 minute. Ferme l\'app et attends.',
            ok: null,
            actionLabel: 'Tester dans 1 min',
            onAction: _test,
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            onPressed: _finish,
            child: const Text('Terminer'),
          ),
        ),
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.number,
    required this.title,
    required this.why,
    required this.ok,
    required this.actionLabel,
    required this.onAction,
    this.secondaryLabel,
    this.onSecondary,
    this.help,
  });

  final int number;
  final String title;
  final String why;
  final bool? ok;
  final String actionLabel;
  final Future<void> Function() onAction;
  final String? secondaryLabel;
  final Future<void> Function()? onSecondary;
  final String? help;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final done = ok == true;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: done
                      ? scheme.primary
                      : scheme.surfaceContainerHighest,
                  foregroundColor: done ? scheme.onPrimary : scheme.onSurface,
                  child: done ? const Icon(Icons.check) : Text('$number'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (ok == false) Icon(Icons.warning_amber, color: scheme.error),
              ],
            ),
            const SizedBox(height: 8),
            Text(why),
            if (help != null && !done) ...[
              const SizedBox(height: 8),
              Text(
                help!,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
            if (!done) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonal(
                    onPressed: onAction,
                    child: Text(actionLabel),
                  ),
                  if (secondaryLabel != null)
                    OutlinedButton(
                      onPressed: onSecondary,
                      child: Text(secondaryLabel!),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
