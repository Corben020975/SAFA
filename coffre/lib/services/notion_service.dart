import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../data/database.dart';

class NotionException implements Exception {
  const NotionException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Base Notion (« source de données ») où envoyer les éléments.
class NotionTarget {
  const NotionTarget({
    required this.id,
    required this.name,
    required this.titleProp,
    this.dateProp,
  });
  final String id;
  final String name;
  final String titleProp;
  final String? dateProp;

  Map<String, String> toMap() => {
    'id': id,
    'name': name,
    'titleProp': titleProp,
    'dateProp': ?dateProp,
  };

  static NotionTarget? fromMap(Map<String, String>? m) =>
      (m == null || m['id'] == null || m['titleProp'] == null)
      ? null
      : NotionTarget(
          id: m['id']!,
          name: m['name'] ?? 'Notion',
          titleProp: m['titleProp']!,
          dateProp: m['dateProp'],
        );
}

class NotionHit {
  const NotionHit(this.title, this.url, this.editedAt);
  final String title;
  final String url;
  final DateTime? editedAt;
}

/// API Notion (version 2025-09-03). Jeton d'« intégration interne » saisi par
/// l'utilisateur ; seules les pages partagées avec l'intégration sont visibles.
class NotionService {
  NotionService(this._token, {http.Client? client})
    : _client = client ?? http.Client();

  final Future<String?> Function() _token;
  final http.Client _client;
  static const version = '2025-09-03';

  Future<bool> get configured async => await _token() != null;

  Future<void> checkToken() async => _call('GET', 'users/me');

  /// Bases (sources de données) partagées avec l'intégration.
  Future<List<NotionTarget>> listTargets() async {
    final json = await _call('POST', 'search', {
      'filter': {'property': 'object', 'value': 'data_source'},
      'page_size': 50,
    });
    return [
      for (final r in (json['results'] as List? ?? const []).whereType<Map>())
        ?targetFrom(r),
    ];
  }

  static NotionTarget? targetFrom(Map r) {
    final props = (r['properties'] as Map? ?? const {});
    String? titleProp, dateProp;
    props.forEach((name, value) {
      final type = (value as Map?)?['type'];
      if (type == 'title') titleProp ??= name as String;
      if (type == 'date') dateProp ??= name as String;
    });
    if (titleProp == null || r['id'] == null) return null;
    return NotionTarget(
      id: r['id'] as String,
      name: plainText(r['title']) ?? 'Sans titre',
      titleProp: titleProp!,
      dateProp: dateProp,
    );
  }

  Future<List<NotionHit>> searchPages(String query) async {
    final json = await _call('POST', 'search', {
      'query': query,
      'filter': {'property': 'object', 'value': 'page'},
      'page_size': 20,
    });
    return [
      for (final r in (json['results'] as List? ?? const []).whereType<Map>())
        if (r['url'] is String)
          NotionHit(
            pageTitle(r) ?? 'Sans titre',
            r['url'] as String,
            DateTime.tryParse('${r['last_edited_time']}'),
          ),
    ];
  }

  /// Crée une page dans la base choisie et renvoie son lien.
  Future<String> createPage(NotionTarget target, Item item) async {
    final json = await _call('POST', 'pages', pageBody(target, item));
    final url = json['url'];
    if (url is! String) {
      throw const NotionException('Page créée, mais lien introuvable.');
    }
    return url;
  }

  static Map<String, Object?> pageBody(NotionTarget target, Item item) {
    final lines = item.content.trim().split('\n');
    final title = lines.first.trim();
    final rest = lines.skip(1).join('\n').trim();
    return {
      'parent': {'type': 'data_source_id', 'data_source_id': target.id},
      'properties': {
        target.titleProp: {
          'title': [
            {
              'type': 'text',
              'text': {'content': _clip(title)},
            },
          ],
        },
        if (target.dateProp != null && item.remindAt != null)
          target.dateProp!: {
            'date': {'start': isoWithOffset(item.remindAt!)},
          },
      },
      'children': [
        for (final paragraph in [
          if (rest.isNotEmpty) rest,
          [
            item.kind.label,
            ?item.context,
            ...item.tags.map((t) => '#$t'),
          ].join(' · '),
        ])
          for (final chunk in _chunks(paragraph))
            {
              'object': 'block',
              'type': 'paragraph',
              'paragraph': {
                'rich_text': [
                  {
                    'type': 'text',
                    'text': {'content': chunk},
                  },
                ],
              },
            },
      ],
    };
  }

  Future<Map<String, dynamic>> _call(
    String method,
    String path, [
    Map<String, Object?>? body,
  ]) async {
    final token = await _token();
    if (token == null) {
      throw const NotionException('Ajoute ton jeton Notion dans Réglages.');
    }
    final uri = Uri.parse('https://api.notion.com/v1/$path');
    final headers = {
      'Authorization': 'Bearer $token',
      'Notion-Version': version,
      'Content-Type': 'application/json',
    };
    final http.Response response;
    try {
      response =
          await (method == 'GET'
                  ? _client.get(uri, headers: headers)
                  : _client.post(
                      uri,
                      headers: headers,
                      body: jsonEncode(body ?? const {}),
                    ))
              .timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw const NotionException('Notion ne répond pas. Réessaie.');
    } on SocketException {
      throw const NotionException('Pas de connexion Internet.');
    } on http.ClientException {
      throw const NotionException('Connexion impossible avec Notion.');
    }
    Map<String, dynamic> json;
    try {
      json =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw NotionException(
        'Réponse illisible de Notion (code ${response.statusCode}).',
      );
    }
    if (response.statusCode == 200) return json;
    throw NotionException(switch (response.statusCode) {
      401 => 'Jeton Notion refusé. Vérifie-le dans Réglages.',
      403 => 'L\'intégration n\'a pas le droit d\'écrire ici.',
      404 => 'Base introuvable : partage-la avec ton intégration Notion (… › Connexions).',
      429 => 'Trop de demandes à Notion. Réessaie dans une minute.',
      _ => 'Erreur Notion (${response.statusCode}) : ${json['message'] ?? ''}',
    });
  }

  static String? plainText(Object? richText) {
    if (richText is! List) return null;
    final text = richText
        .whereType<Map>()
        .map((t) => t['plain_text'] ?? '')
        .join()
        .trim();
    return text.isEmpty ? null : text;
  }

  static String? pageTitle(Map page) {
    String? title;
    (page['properties'] as Map? ?? const {}).forEach((_, value) {
      if (value is Map && value['type'] == 'title') {
        title ??= plainText(value['title']);
      }
    });
    return title;
  }

  /// « 2026-09-29T09:00:00+02:00 » : Notion garde l'heure locale exacte.
  static String isoWithOffset(DateTime local) {
    final d = local.toLocal();
    final offset = d.timeZoneOffset;
    final sign = offset.isNegative ? '-' : '+';
    final h = offset.inHours.abs().toString().padLeft(2, '0');
    final m = (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}T${two(d.hour)}:${two(d.minute)}:00$sign$h:$m';
  }

  static String _clip(String s) => s.length > 2000 ? s.substring(0, 2000) : s;

  /// Notion limite chaque bloc de texte à 2000 caractères.
  static Iterable<String> _chunks(String s) sync* {
    for (var i = 0; i < s.length; i += 1900) {
      yield s.substring(i, i + 1900 > s.length ? s.length : i + 1900);
    }
  }
}
