import 'package:flutter/material.dart';

import '../../services/app_lock.dart';
import '../theme.dart';

/// Écran opaque posé au-dessus de l'app tant que Coffre est verrouillé.
class LockScreen extends StatefulWidget {
  const LockScreen({super.key, required this.lock});
  final AppLock lock;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  @override
  void initState() {
    super.initState();
    FocusManager.instance.primaryFocus?.unfocus();
    // Propose l'empreinte tout de suite, sans devoir toucher le bouton.
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.lock.unlock());
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final theme = Theme.of(context);
    return Material(
      color: theme.scaffoldBackgroundColor,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: ListenableBuilder(
              listenable: widget.lock,
              builder: (context, _) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock_outline, size: 56, color: p.sage),
                  const SizedBox(height: 20),
                  Text(
                    'Coffre est verrouillé',
                    style: displayStyle(context, 26),
                  ),
                  const SizedBox(height: 28),
                  FilledButton.icon(
                    onPressed: widget.lock.unlock,
                    icon: const Icon(Icons.fingerprint),
                    label: const Text('Déverrouiller'),
                  ),
                  if (widget.lock.error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      widget.lock.error!,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: p.coral,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
