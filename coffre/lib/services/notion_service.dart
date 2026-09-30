import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../core/reminder_defaults.dart';
import '../data/database.dart';
import '../data/enums.dart';

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

/// Tâche lue dans une base Notion.
class NotionTask {
  const NotionTask({
    this.id,
    required this.url,
    required this.title,
    this.note,
    this.due,
    this.done = false,
    this.doing = false,
    this.priority = ItemPriority.normal,
    this.tags = const [],
  });
  final String? id;
  final String url;
  final String title;
  final String? note;
  final DateTime? due;
  final bool done;
  final bool doing;
  final ItemPriority priority;

  /// Valeurs des listes (Contexte, Domaine…) et statuts particuliers
  /// (Bloqué, Délégué…), en minuscules.
  final List<String> tags;
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

  /// Toutes les lignes de la base (500 max), terminées comprises.
  Future<List<NotionTask>> fetchTasks(NotionTarget target) async {
    final schema = await _call('GET', 'data_sources/${target.id}');
    final complete = completeOptionIds(schema);
    final tasks = <NotionTask>[];
    String? cursor;
    do {
      final json = await _call('POST', 'data_sources/${target.id}/query', {
        'page_size': 100,
        'start_cursor': ?cursor,
      });
      for (final page
          in (json['results'] as List? ?? const []).whereType<Map>()) {
        if (page['in_trash'] == true || page['archived'] == true) continue;
        final task = taskFrom(page, complete, dateProp: target.dateProp);
        if (task != null) tasks.add(task);
      }
      cursor = json['has_more'] == true ? json['next_cursor'] as String? : null;
    } while (cursor != null && tasks.length < 500);
    return tasks;
  }

  /// Options de statut rangées dans le groupe « Terminé » / « Complete ».
  static Set<String> completeOptionIds(Map schema) {
    final ids = <String>{};
    for (final prop in (schema['properties'] as Map? ?? const {}).values) {
      if (prop is! Map || prop['type'] != 'status') continue;
      for (final group
          in ((prop['status'] as Map?)?['groups'] as List? ?? const [])
              .whereType<Map>()) {
        if (_completeGroup.hasMatch('${group['name']}')) {
          ids.addAll(
            (group['option_ids'] as List? ?? const []).whereType<String>(),
          );
        }
      }
    }
    return ids;
  }

  static final _completeGroup = RegExp(r'complet|termin', caseSensitive: false);
  static final _doneName = RegExp(
    r'termin|fait\b|done|complet|clos|fini|archiv|annul',
    caseSensitive: false,
  );
  static final _negated = RegExp(r'\b(pas|non|not)\b', caseSensitive: false);
  static bool _isDone(String label) =>
      _doneName.hasMatch(label) && !_negated.hasMatch(label);
  static final _doingName = RegExp(
    r'en cours|in progress|commenc|started|doing',
    caseSensitive: false,
  );
  static final _doneCheckbox = RegExp(
    r'fait|termin|done|complet|fini|coch',
    caseSensitive: false,
  );
  static final _noteName = RegExp(
    r'note|descr|d[ée]tail|comment',
    caseSensitive: false,
  );

  /// Ligne Notion → tâche Coffre. Statut, case à cocher, date et priorité
  /// sont reconnus par leur type et leur nom (français ou anglais).
  static final _statusName = RegExp(
    r'statut|status|[ée]tat',
    caseSensitive: false,
  );
  static final _todoName = RegExp(
    r'faire|to ?do|pas commenc|not started|nouveau|new|backlog',
    caseSensitive: false,
  );

  /// Ligne Notion → tâche Coffre. Statut, case à cocher, date, priorité et
  /// listes sont reconnus par leur type et leur nom (français ou anglais).
  static NotionTask? taskFrom(
    Map page,
    Set<String> completeIds, {
    String? dateProp,
  }) {
    final url = page['url'];
    final title = pageTitle(page);
    if (url is! String || title == null) return null;
    final props = (page['properties'] as Map? ?? const {})
        .cast<Object?, Object?>();
    var done = false, doing = false;
    var priority = ItemPriority.normal;
    DateTime? due;
    String? note;
    final tags = <String>[];

    void status(String label, {bool complete = false}) {
      if (complete || _isDone(label)) {
        done = true;
      } else if (_doingName.hasMatch(label)) {
        doing = true;
      } else if (label.trim().isNotEmpty && !_todoName.hasMatch(label)) {
        tags.add(label.trim().toLowerCase()); // Bloqué, Délégué, Reporté…
      }
    }

    props.forEach((key, value) {
      if (value is! Map) return;
      final name = '$key';
      final isPriority = name.toLowerCase().contains('priorit');
      switch (value['type']) {
        case 'status':
          final s = value['status'] as Map?;
          final label = '${s?['name'] ?? ''}';
          if (isPriority) {
            priority = _priority(label);
          } else {
            status(label, complete: completeIds.contains(s?['id']));
          }
        case 'checkbox':
          // Seulement une case nommée « Fait », « Terminé »… (pas « Récurrente »).
          if (value['checkbox'] == true && _doneCheckbox.hasMatch(name)) {
            done = true;
          }
        case 'select':
          final label = '${(value['select'] as Map?)?['name'] ?? ''}';
          if (label.isEmpty) break;
          if (isPriority) {
            priority = _priority(label);
          } else if (_statusName.hasMatch(name)) {
            status(label);
          } else {
            tags.add(label.toLowerCase());
          }
        case 'multi_select':
          for (final option
              in (value['multi_select'] as List? ?? const [])
                  .whereType<Map>()) {
            final label = '${option['name'] ?? ''}'.trim();
            if (label.isNotEmpty) tags.add(label.toLowerCase());
          }
        case 'date':
          if (dateProp == null || dateProp == name) {
            due ??= parseDate((value['date'] as Map?)?['start'] as String?);
          }
        case 'rich_text':
          final text = plainText(value['rich_text']);
          if (text == null) break;
          if (isPriority) {
            priority = _priority(text);
          } else if (_noteName.hasMatch(name)) {
            note ??= text;
          }
      }
    });
    return NotionTask(
      id: page['id'] as String?,
      url: url,
      title: title,
      note: note,
      due: due,
      done: done,
      doing: doing,
      priority: priority,
      tags: tags.toSet().toList(),
    );
  }

  /// Texte de la page (paragraphes, titres, listes, cases), 100 blocs max.
  Future<String?> pageText(String pageId) async {
    final json = await _call('GET', 'blocks/$pageId/children?page_size=100');
    return blocksText(json['results'] as List? ?? const []);
  }

  static String? blocksText(List blocks) {
    final lines = <String>[];
    for (final block in blocks.whereType<Map>()) {
      final type = block['type'] as String?;
      final data = block[type] as Map?;
      final text = plainText(data?['rich_text']);
      if (text == null) continue;
      lines.add(switch (type) {
        'bulleted_list_item' => '- $text',
        'numbered_list_item' => '- $text',
        'to_do' => '${data?['checked'] == true ? '☑' : '☐'} $text',
        _ => text,
      });
    }
    return lines.isEmpty ? null : lines.join('\n');
  }

  /// Coffre → Notion : passe la page à « Fait » (statut, liste ou case).
  /// Renvoie false si la base n'a rien d'équivalent.
  Future<bool> markDone(String pageUrl) async {
    final id = pageIdFromUrl(pageUrl);
    if (id == null) return false;
    final page = await _call('GET', 'pages/$id');
    final dataSource = (page['parent'] as Map?)?['data_source_id'] as String?;
    final schema = dataSource == null
        ? const <String, dynamic>{}
        : await _call('GET', 'data_sources/$dataSource');
    final update = doneUpdate(page['properties'] as Map? ?? const {}, schema);
    if (update == null) return false;
    await _call('PATCH', 'pages/$id', {'properties': update});
    return true;
  }

  static String? pageIdFromUrl(String url) {
    // « …/Titre-de-la-page-3ea7e7c722f3… » : l'identifiant termine le chemin.
    final path = (Uri.tryParse(url)?.path ?? '').replaceAll('-', '');
    return RegExp(r'[0-9a-f]{32}$').firstMatch(path)?.group(0);
  }

  /// Propriété à modifier pour clore la page, d'après le schéma de la base.
  static Map<String, Object?>? doneUpdate(Map pageProps, Map schema) {
    final schemaProps = schema['properties'] as Map? ?? const {};
    for (final entry in pageProps.entries) {
      final name = '${entry.key}';
      final value = entry.value;
      if (value is! Map || name.toLowerCase().contains('priorit')) continue;
      final config = schemaProps[name] as Map?;
      switch (value['type']) {
        case 'status':
          final status = config?['status'] as Map?;
          final options = (status?['options'] as List? ?? const [])
              .whereType<Map>()
              .toList();
          String? target;
          for (final group
              in (status?['groups'] as List? ?? const []).whereType<Map>()) {
            if (!_completeGroup.hasMatch('${group['name']}')) continue;
            final ids = (group['option_ids'] as List? ?? const []).toSet();
            target = options
                .where((o) => ids.contains(o['id']))
                .map((o) => '${o['name']}')
                .firstOrNull;
            if (target != null) break;
          }
          target ??= options
              .map((o) => '${o['name']}')
              .where(_isDone)
              .firstOrNull;
          if (target != null) {
            return {
              name: {
                'status': {'name': target},
              },
            };
          }
        case 'select' when _statusName.hasMatch(name):
          final target =
              ((config?['select'] as Map?)?['options'] as List? ?? const [])
                  .whereType<Map>()
                  .map((o) => '${o['name']}')
                  .where(_isDone)
                  .firstOrNull;
          if (target != null) {
            return {
              name: {
                'select': {'name': target},
              },
            };
          }
        case 'checkbox' when _doneCheckbox.hasMatch(name):
          return {
            name: {'checkbox': true},
          };
      }
    }
    return null;
  }

  static ItemPriority _priority(String label) {
    final l = label.toLowerCase().trim();
    // P1 / P2 / P3 (P0 = urgent).
    final p = RegExp(r'^p\s*([0-3])\b').firstMatch(l);
    if (p != null) {
      return const [
        ItemPriority.urgent,
        ItemPriority.high,
        ItemPriority.normal,
        ItemPriority.low,
      ][int.parse(p.group(1)!)];
    }
    if (l.contains('urgent')) return ItemPriority.urgent;
    if (RegExp(r'haut|high|[ée]lev|important').hasMatch(l)) {
      return ItemPriority.high;
    }
    if (RegExp(r'bas|low|faibl').hasMatch(l)) return ItemPriority.low;
    return ItemPriority.normal;
  }

  /// « 2026-09-29 » → heure du matin par défaut ; sinon date et heure exactes.
  static DateTime? parseDate(String? start) {
    if (start == null) return null;
    if (start.length == 10) {
      final day = DateTime.tryParse(start);
      if (day == null) return null;
      final (hour, minute) = ReminderDefaults.morning;
      return DateTime(day.year, day.month, day.day, hour, minute);
    }
    return DateTime.tryParse(start)?.toLocal();
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
      response = await switch (method) {
        'GET' => _client.get(uri, headers: headers),
        'PATCH' => _client.patch(
          uri,
          headers: headers,
          body: jsonEncode(body ?? const {}),
        ),
        _ => _client.post(
          uri,
          headers: headers,
          body: jsonEncode(body ?? const {}),
        ),
      }.timeout(const Duration(seconds: 30));
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
