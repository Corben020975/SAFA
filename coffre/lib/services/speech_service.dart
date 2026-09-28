import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart';

enum DictationState { idle, listening, unavailable }

/// Dictée via le moteur de reconnaissance du téléphone (Google ou Samsung).
/// L'app n'a pas accès à Internet : si le moteur envoie l'audio en ligne,
/// c'est lui qui le fait. L'option « sur l'appareil uniquement » l'interdit.
class SpeechService extends ChangeNotifier {
  final SpeechToText _stt = SpeechToText();

  DictationState state = DictationState.idle;
  String partialText = '';
  double level = 0;
  String? lastError;

  bool _initialized = false;
  List<String> _locales = const [];

  bool get isListening => state == DictationState.listening;

  /// Déclenche la demande de permission micro au premier appel.
  Future<bool> ensureReady() async {
    if (_initialized) return _stt.isAvailable;
    _initialized = true;
    final ok = await _stt.initialize(
      onError: _onError,
      onStatus: _onStatus,
      options: [SpeechToText.androidNoBluetooth],
    );
    if (ok) {
      try {
        _locales = (await _stt.locales())
            .map((l) => l.localeId.replaceAll('-', '_').toLowerCase())
            .toList();
      } catch (_) {}
    } else {
      state = DictationState.unavailable;
      notifyListeners();
    }
    return ok;
  }

  Future<bool> get hasPermission => _stt.hasPermission;

  /// [onFinal] reçoit le texte reconnu à la fin de la phrase.
  Future<bool> start({
    required String preferredLocale,
    required bool onDeviceOnly,
    required void Function(String text) onFinal,
  }) async {
    if (!await ensureReady()) {
      lastError = 'Dictée indisponible (micro refusé ou pas de moteur vocal).';
      notifyListeners();
      return false;
    }
    lastError = null;
    partialText = '';
    state = DictationState.listening;
    notifyListeners();
    await _stt.listen(
      onResult: (result) {
        partialText = result.recognizedWords;
        if (result.finalResult) {
          final text = result.recognizedWords.trim();
          partialText = '';
          if (text.isNotEmpty) onFinal(text);
        }
        notifyListeners();
      },
      onSoundLevelChange: (value) {
        level = value;
        notifyListeners();
      },
      listenOptions: SpeechListenOptions(
        localeId: _pickLocale(preferredLocale),
        listenMode: ListenMode.dictation,
        partialResults: true,
        onDevice: onDeviceOnly,
        cancelOnError: true,
        autoPunctuation: true,
        listenFor: const Duration(minutes: 1),
        pauseFor: const Duration(seconds: 4),
      ),
    );
    return true;
  }

  Future<void> stop() async {
    await _stt.stop();
    state = DictationState.idle;
    notifyListeners();
  }

  /// Langue choisie si le moteur la propose, sinon fr_BE, fr_FR, puis
  /// n'importe quel français. Liste vide (certains moteurs Samsung) : on tente.
  String _pickLocale(String preferred) {
    if (_locales.isEmpty) return preferred;
    for (final candidate in [preferred, 'fr_BE', 'fr_FR']) {
      if (_locales.contains(candidate.toLowerCase())) return candidate;
    }
    return _locales.where((l) => l.startsWith('fr')).firstOrNull ?? preferred;
  }

  void _onStatus(String status) {
    if (status == SpeechToText.doneStatus ||
        status == SpeechToText.notListeningStatus) {
      state = DictationState.idle;
      level = 0;
      notifyListeners();
    }
  }

  void _onError(SpeechRecognitionError error) {
    state = DictationState.idle;
    level = 0;
    lastError = switch (error.errorMsg) {
      'error_no_match' || 'error_speech_timeout' =>
        'Rien entendu. Touche le micro et parle.',
      'error_language_not_supported' || 'error_language_unavailable' =>
        'Français indisponible hors-ligne : installe le pack « Français » '
            'dans la reconnaissance vocale du téléphone, ou désactive '
            '« sur l\'appareil uniquement » dans Réglages.',
      'error_permission' || 'error_insufficient_permissions' =>
        'Micro refusé. Autorise-le dans Réglages > Applications > Coffre.',
      'error_network' || 'error_network_timeout' || 'error_server' =>
        'Le moteur vocal a besoin d\'Internet : installe le pack hors-ligne '
            'français ou utilise le clavier.',
      'error_busy' => 'Micro occupé par une autre app. Réessaie.',
      _ => 'Dictée interrompue (${error.errorMsg}). Tu peux continuer au clavier.',
    };
    notifyListeners();
  }
}
