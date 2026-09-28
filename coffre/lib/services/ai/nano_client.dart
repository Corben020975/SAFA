import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'ai_engine.dart';
import 'claude_client.dart';

enum NanoStatus { available, downloadable, downloading, unavailable }

/// Progression du téléchargement du modèle (octets).
class NanoProgress {
  const NanoProgress(this.done, this.total);
  final int done;
  final int total;

  double? get ratio => total > 0 ? (done / total).clamp(0, 1).toDouble() : null;
}

/// Gemini Nano via ML Kit GenAI (MainActivity › NanoBridge).
/// Rien ne quitte le téléphone : pas de masquage nécessaire.
class NanoClient implements AiEngine {
  static const _channel = MethodChannel('coffre/nano');

  /// Contexte du modèle ≈ 4 000 jetons : on borne l'entrée.
  static const maxInputChars = 6000;

  /// Non nul pendant un téléchargement lancé par Coffre.
  final progress = ValueNotifier<NanoProgress?>(null);
  Future<void>? _download;
  String? lastError;

  bool get downloading => _download != null;

  Future<NanoStatus> status() async {
    try {
      final raw = await _channel.invokeMapMethod<String, Object?>('status');
      lastError = raw?['error'] as String?;
      return NanoStatus.values.asNameMap()[raw?['status']] ??
          NanoStatus.unavailable;
    } on MissingPluginException {
      return NanoStatus.unavailable; // tests / hors Android
    } on PlatformException catch (e) {
      lastError = e.message;
      return NanoStatus.unavailable;
    }
  }

  /// Un seul téléchargement à la fois ; les appels suivants s'y rattachent.
  Future<void> download() => _download ??= _runDownload().whenComplete(() {
    _download = null;
    progress.value = null;
  });

  Future<void> _runDownload() async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'progress' && call.arguments is Map) {
        final m = call.arguments as Map;
        progress.value = NanoProgress(
          (m['done'] as num?)?.toInt() ?? 0,
          (m['total'] as num?)?.toInt() ?? 0,
        );
      }
    });
    progress.value = const NanoProgress(0, 0);
    try {
      await _channel.invokeMethod<bool>('download');
    } on MissingPluginException {
      throw const AiException('Gemini Nano n\'est pas disponible ici.');
    } on PlatformException catch (e) {
      throw AiException('Téléchargement impossible : ${e.message ?? e.code}');
    }
  }

  @override
  Future<String> complete({
    required String system,
    required String prompt,
    String effort = 'low',
  }) async {
    final input = prompt.length > maxInputChars
        ? '${prompt.substring(0, maxInputChars)}…'
        : prompt;
    try {
      final text = await _channel
          .invokeMethod<String>('generate', {
            'system': system,
            'prompt': input,
            'maxTokens': effort == 'low' ? 512 : 1024,
          })
          .timeout(const Duration(minutes: 2));
      if (text == null || text.trim().isEmpty) {
        throw const AiException(
          'Gemini Nano n\'a rien répondu. Reformule ou raccourcis le texte.',
        );
      }
      return text.trim();
    } on TimeoutException {
      throw const AiException('Gemini Nano met trop de temps. Réessaie.');
    } on MissingPluginException {
      throw const AiException('Gemini Nano n\'est pas disponible ici.');
    } on PlatformException catch (e) {
      throw AiException(message(e.message ?? e.code));
    }
  }

  /// Erreurs AICore (en anglais) → message clair.
  static String message(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('background')) {
      return 'Garde Coffre ouvert pendant que Gemini Nano répond.';
    }
    if (lower.contains('busy') || lower.contains('quota')) {
      return 'Gemini Nano est occupé. Réessaie dans un instant.';
    }
    if (lower.contains('not available') ||
        lower.contains('not_available') ||
        lower.contains('download')) {
      return 'Le modèle Gemini Nano n\'est pas prêt. Réglages › Assistant IA.';
    }
    return 'Gemini Nano : $raw';
  }
}
