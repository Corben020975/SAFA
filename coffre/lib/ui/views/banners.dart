import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../theme.dart';

/// Visible tant qu'un réglage Samsung empêche des rappels fiables.
class ReminderHealthBanner extends StatefulWidget {
  const ReminderHealthBanner({super.key});

  @override
  State<ReminderHealthBanner> createState() => _ReminderHealthBannerState();
}

class _ReminderHealthBannerState extends State<ReminderHealthBanner> {
  late final AppServices _s = AppScope.of(context);
  late final AppLifecycleListener _lifecycle;
  bool _healthy = true;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _check);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _check();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    final ok =
        await _s.notifications.areEnabled() &&
        await _s.notifications.canScheduleExact() &&
        await _s.system.isIgnoringBatteryOptimizations();
    if (mounted && ok != _healthy) setState(() => _healthy = ok);
  }

  @override
  Widget build(BuildContext context) {
    if (_healthy) return const SizedBox.shrink();
    final p = Palette.of(context);
    return _BannerCard(
      icon: Icons.notifications_off_outlined,
      title: 'Rappels pas encore fiables',
      text: 'Un réglage Samsung manque. Touche pour corriger.',
      color: p.coral,
      onTap: () async {
        await Navigator.of(context).pushNamed('/onboarding');
        _check();
      },
    );
  }
}

/// Base précédente illisible (clé perdue) : invite à restaurer un export JSON.
class SetAsideBanner extends StatefulWidget {
  const SetAsideBanner({super.key});

  @override
  State<SetAsideBanner> createState() => _SetAsideBannerState();
}

class _SetAsideBannerState extends State<SetAsideBanner> {
  bool _dismissed = false;

  @override
  Widget build(BuildContext context) {
    final file = AppScope.of(context).setAsideDbFile;
    if (file == null || _dismissed) return const SizedBox.shrink();
    return _BannerCard(
      icon: Icons.restore,
      title: 'Ancienne base illisible',
      text:
          'La clé de chiffrement a été perdue. L\'ancien fichier est conservé ($file). '
          'Restaure ta dernière sauvegarde JSON depuis Réglages.',
      color: Palette.of(context).sand,
      onTap: () => Navigator.of(context).pushNamed('/settings'),
      onClose: () => setState(() => _dismissed = true),
    );
  }
}

class _BannerCard extends StatelessWidget {
  const _BannerCard({
    required this.icon,
    required this.title,
    required this.text,
    required this.color,
    required this.onTap,
    this.onClose,
  });

  final IconData icon;
  final String title;
  final String text;
  final Color color;
  final VoidCallback onTap;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Material(
        color: color.withValues(alpha: 0.12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: color.withValues(alpha: 0.35)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: color,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(text, style: theme.textTheme.bodyMedium),
                    ],
                  ),
                ),
                if (onClose != null)
                  IconButton(
                    tooltip: 'Fermer',
                    onPressed: onClose,
                    icon: const Icon(Icons.close, size: 20),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
