import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class AiException implements Exception {
  const AiException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Appel direct de l'API Claude (Messages) en HTTP : il n'existe pas de SDK
/// Anthropic officiel pour Dart/Flutter.
class ClaudeClient {
  ClaudeClient(this._apiKey, {http.Client? client})
    : _client = client ?? http.Client();

  final Future<String?> Function() _apiKey;
  final http.Client _client;

  static const model = 'claude-opus-5';
  static final _endpoint = Uri.parse('https://api.anthropic.com/v1/messages');

  /// Corps de requête. `fallbacks: "default"` : si les filtres de sécurité
  /// déclinent la demande, Anthropic la relance d'office sur le modèle de repli
  /// recommandé au lieu de renvoyer un refus.
  static Map<String, Object?> buildBody({
    required String system,
    required String prompt,
    required String effort,
    int maxTokens = 16000,
  }) => {
    'model': model,
    'max_tokens': maxTokens,
    'fallbacks': 'default',
    'output_config': {'effort': effort},
    'system': system,
    'messages': [
      {'role': 'user', 'content': prompt},
    ],
  };

  Future<String> complete({
    required String system,
    required String prompt,
    String effort = 'low',
  }) async {
    final key = await _apiKey();
    if (key == null) {
      throw const AiException(
        'Ajoute ta clé API Claude dans Réglages › Assistant IA.',
      );
    }
    final http.Response response;
    try {
      response = await _client
          .post(
            _endpoint,
            headers: {
              'content-type': 'application/json',
              'x-api-key': key,
              'anthropic-version': '2023-06-01',
              'anthropic-beta': 'server-side-fallback-2026-07-01',
            },
            body: jsonEncode(
              buildBody(system: system, prompt: prompt, effort: effort),
            ),
          )
          .timeout(const Duration(seconds: 120));
    } on TimeoutException {
      throw const AiException('Claude met trop de temps à répondre. Réessaie.');
    } on SocketException {
      throw const AiException('Pas de connexion Internet.');
    } on http.ClientException {
      throw const AiException('Connexion impossible avec Claude.');
    }
    return parse(response.statusCode, utf8.decode(response.bodyBytes));
  }

  /// Interprète la réponse : erreurs HTTP traduites, refus, blocs de texte.
  static String parse(int status, String body) {
    Map<String, dynamic> json;
    try {
      json = jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      throw AiException('Réponse illisible de Claude (code $status).');
    }
    if (status != 200) {
      final detail = (json['error'] as Map?)?['message'] as String?;
      throw AiException(switch (status) {
        401 => 'Clé API refusée. Vérifie-la dans Réglages.',
        403 => 'Cette clé n\'a pas accès à ce modèle.',
        429 => 'Trop de demandes pour l\'instant. Réessaie dans une minute.',
        529 ||
        500 ||
        502 ||
        503 => 'Claude est surchargé. Réessaie dans un moment.',
        400 when (detail ?? '').contains('credit') =>
          'Crédit API épuisé (console.anthropic.com).',
        _ => 'Erreur Claude ($status)${detail == null ? '' : ' : $detail'}',
      });
    }
    // Toujours vérifier le refus avant de lire le contenu.
    if (json['stop_reason'] == 'refusal') {
      throw const AiException('Claude a décliné cette demande.');
    }
    final texts = (json['content'] as List? ?? const [])
        .whereType<Map>()
        .where((block) => block['type'] == 'text')
        .map((block) => block['text'] as String? ?? '')
        .where((t) => t.trim().isNotEmpty);
    final text = texts.join('\n\n').trim();
    if (text.isEmpty) throw const AiException('Réponse vide de Claude.');
    return json['stop_reason'] == 'max_tokens' ? '$text…' : text;
  }
}
