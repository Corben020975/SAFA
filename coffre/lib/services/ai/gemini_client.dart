import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'ai_engine.dart';
import 'claude_client.dart';

/// API Gemini (Google AI Studio) en HTTP. Clé gratuite, avec quotas.
class GeminiClient implements AiEngine {
  GeminiClient(this._apiKey, {http.Client? client})
    : _client = client ?? http.Client();

  final Future<String?> Function() _apiKey;
  final http.Client _client;

  /// Alias maintenu par Google vers le dernier Flash ; repli s'il disparaît.
  static const models = ['gemini-flash-latest', 'gemini-2.5-flash'];

  static Uri endpoint(String model) => Uri.parse(
    'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent',
  );

  static Map<String, Object?> buildBody({
    required String system,
    required String prompt,
    int maxTokens = 8192,
  }) => {
    'systemInstruction': {
      'parts': [
        {'text': system},
      ],
    },
    'contents': [
      {
        'role': 'user',
        'parts': [
          {'text': prompt},
        ],
      },
    ],
    'generationConfig': {'temperature': 0.4, 'maxOutputTokens': maxTokens},
  };

  /// `effort` est ignoré : Gemini règle seul sa réflexion.
  @override
  Future<String> complete({
    required String system,
    required String prompt,
    String effort = 'low',
  }) async {
    final key = await _apiKey();
    if (key == null) {
      throw const AiException(
        'Ajoute ta clé API Gemini dans Réglages › Assistant IA.',
      );
    }
    final body = jsonEncode(buildBody(system: system, prompt: prompt));
    for (var i = 0; ; i++) {
      final response = await _post(models[i], key, body);
      // Modèle retiré ou renommé : on passe au suivant.
      if (response.statusCode == 404 && i < models.length - 1) continue;
      return parse(response.statusCode, utf8.decode(response.bodyBytes));
    }
  }

  Future<http.Response> _post(String model, String key, String body) async {
    try {
      return await _client
          .post(
            endpoint(model),
            headers: {
              'content-type': 'application/json',
              'x-goog-api-key': key,
            },
            body: body,
          )
          .timeout(const Duration(seconds: 120));
    } on TimeoutException {
      throw const AiException('Gemini met trop de temps à répondre. Réessaie.');
    } on SocketException {
      throw const AiException('Pas de connexion Internet.');
    } on http.ClientException {
      throw const AiException('Connexion impossible avec Gemini.');
    }
  }

  /// Interprète la réponse : erreurs HTTP traduites, blocages, texte.
  static String parse(int status, String body) {
    Map<String, dynamic> json;
    try {
      json = jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      throw AiException('Réponse illisible de Gemini (code $status).');
    }
    if (status != 200) {
      final error = json['error'] as Map?;
      final detail = error?['message'] as String?;
      final reasons = jsonEncode(error?['details'] ?? const []);
      throw AiException(switch (status) {
        400 when reasons.contains('API_KEY_INVALID') =>
          'Clé API refusée. Vérifie-la dans Réglages.',
        400 when (detail ?? '').contains('location') =>
          'Gemini n\'est pas accessible depuis ce pays avec cette clé.',
        401 || 403 => 'Clé API refusée ou sans accès à Gemini.',
        429 =>
          'Quota gratuit atteint. Réessaie dans une minute '
              '(ou demain si c\'est la limite du jour).',
        500 ||
        502 ||
        503 ||
        504 => 'Gemini est surchargé. Réessaie dans un moment.',
        _ => 'Erreur Gemini ($status)${detail == null ? '' : ' : $detail'}',
      });
    }
    if ((json['promptFeedback'] as Map?)?['blockReason'] != null) {
      throw const AiException(
        'Gemini a bloqué cette demande (filtres de sécurité).',
      );
    }
    final candidate = (json['candidates'] as List? ?? const [])
        .whereType<Map>()
        .firstOrNull;
    final finish = candidate?['finishReason'] as String?;
    final text =
        ((candidate?['content'] as Map?)?['parts'] as List? ?? const [])
            .whereType<Map>()
            .where((part) => part['thought'] != true)
            .map((part) => part['text'] as String? ?? '')
            .join()
            .trim();
    if (text.isEmpty) {
      throw AiException(switch (finish) {
        'SAFETY' ||
        'PROHIBITED_CONTENT' ||
        'BLOCKLIST' ||
        'SPII' => 'Gemini a bloqué cette réponse (filtres de sécurité).',
        'MAX_TOKENS' => 'Réponse trop longue pour Gemini. Raccourcis le texte.',
        _ => 'Réponse vide de Gemini.',
      });
    }
    return finish == 'MAX_TOKENS' ? '$text…' : text;
  }
}
