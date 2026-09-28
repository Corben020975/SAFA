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
    required this.url,
    required this.title,
    this.note,
    this.due,
    this.done = false,
    this.doing = false,
    this.priority = ItemPriority.normal,
  });
  final String url;
  final String title;
  final String? note;
  final DateTime? due;
  final bool done;
  final bool doing;
  final ItemPriority priority;
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
    final checkboxes = props.values
        .whereType<Map>()
        .where((v) => v['type'] == 'checkbox')
        .length;
    var done = false, doing = false;
    var priority = ItemPriority.normal;
    DateTime? due;
    String? note;
    props.forEach((key, value) {
      if (value is! Map) return;
      final name = '$key';
      switch (value['type']) {
        case 'status':
          final status = value['status'] as Map?;
          final label = '${status?['name'] ?? ''}';
          if (completeIds.contains(status?['id']) || _isDone(label)) {
            done = true;
          } else if (_doingName.hasMatch(label)) {
            doing = true;
          }
          if (name.toLowerCase().contains('priorit')) {
            priority = _priority(label);
          }
        case 'checkbox':
          if (value['checkbox'] == true &&
              (checkboxes == 1 || _doneCheckbox.hasMatch(name))) {
            done = true;
          }
        case 'select':
          final label = '${(value['select'] as Map?)?['name'] ?? ''}';
          if (name.toLowerCase().contains('priorit')) {
            priority = _priority(label);
          } else if (RegExp(
            r'statut|status|[ée]tat',
            caseSensitive: false,
          ).hasMatch(name)) {
            if (_isDone(label)) done = true;
            if (_doingName.hasMatch(label)) doing = true;
          }
        case 'date':
          if (dateProp == null || dateProp == name) {
            due ??= parseDate((value['date'] as Map?)?['start'] as String?);
          }
        case 'rich_text':
          if (_noteName.hasMatch(name)) note ??= plainText(value['rich_text']);
      }
    });
    return NotionTask(
      url: url,
      title: title,
      note: note,
      due: due,
      done: done,
      doing: doing,
      priority: priority,
    );
  }

  static ItemPriority _priority(String label) {
    final l = label.toLowerCase();
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
