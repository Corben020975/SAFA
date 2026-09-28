import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../services/speech_service.dart';

/// Gros bouton micro + retour visuel (texte partiel, niveau sonore, erreurs).
/// Le texte reconnu est AJOUTÉ au champ : on peut dicter en plusieurs fois
/// (Android coupe l'écoute après quelques secondes de silence).
class DictationPanel extends StatelessWidget {
  const DictationPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final speech = AppScope.of(context).speech;
    final scheme = Theme.of(context).colorScheme;

    return ListenableBuilder(
      listenable: speech,
      builder: (context, _) {
        final listening = speech.isListening;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (listening)
              Card(
                color: scheme.secondaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('J\'écoute…', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: ((speech.level + 2) / 12).clamp(0.05, 1.0),
                        minHeight: 6,
                        borderRadius: BorderRadius.circular(3),
                      ),
                      if (speech.partialText.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(speech.partialText, style: Theme.of(context).textTheme.bodyLarge),
                      ],
                    ],
                  ),
                ),
              ),
            if (!listening && speech.lastError != null)
              Card(
                color: scheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    speech.lastError!,
                    style: TextStyle(color: scheme.onErrorContainer),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class MicButton extends StatelessWidget {
  const MicButton({super.key, required this.onText, this.large = false});
  final ValueChanged<String> onText;
  final bool large;

  static Future<void> toggle(BuildContext context, ValueChanged<String> onText) async {
    final services = AppScope.of(context);
    final speech = services.speech;
    if (speech.isListening) {
      await speech.stop();
      return;
    }
    await speech.start(
      preferredLocale: services.settings.dictationLocale,
      onDeviceOnly: services.settings.onDeviceDictation,
      onFinal: onText,
    );
  }

  @override
  Widget build(BuildContext context) {
    final speech = AppScope.of(context).speech;
    return ListenableBuilder(
      listenable: speech,
      builder: (context, _) {
        final listening = speech.state == DictationState.listening;
        final icon = Icon(listening ? Icons.stop : Icons.mic, size: large ? 30 : 24);
        final tooltip = listening ? 'Arrêter la dictée' : 'Dicter';
        return large
            ? SizedBox(
                width: 64,
                height: 56,
                child: IconButton.filledTonal(
                  tooltip: tooltip,
                  onPressed: () => toggle(context, onText),
                  icon: icon,
                ),
              )
            : IconButton(
                tooltip: tooltip,
                onPressed: () => toggle(context, onText),
                icon: icon,
              );
      },
    );
  }
}

/// Ajoute un fragment dicté au texte existant, avec un espace ou un saut de ligne.
String appendDictation(String current, String dictated) {
  final text = dictated.trim();
  if (text.isEmpty) return current;
  final capitalized = text[0].toUpperCase() + text.substring(1);
  if (current.trim().isEmpty) return capitalized;
  final sep = current.endsWith('\n') || current.endsWith(' ') ? '' : ' ';
  return '$current$sep$text';
}
