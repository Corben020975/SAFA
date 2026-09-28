import 'dart:convert';

import 'package:drift/drift.dart';

import '../core/date_labels.dart';
import '../core/text_normalize.dart';
import '../services/notification_service.dart';
import '../services/system_channel.dart';
import 'database.dart';
import 'enums.dart';

class ImportReport {
  const ImportReport(this.added, this.skipped);
  final int added;
  final int skipped;
}

/// Export JSON (sauvegarde restaurable) et CSV (lecture dans Excel), import JSON.
/// Les fichiers sont écrits là où l'utilisateur le choisit via le sélecteur
/// Android : rien ne quitte le téléphone sans action explicite.
/// ATTENTION : un export est en clair (non chiffré).
class BackupService {
  BackupService(this._db, this._system, this._notifications);
  final AppDatabase _db;
  final SystemChannel _system;
  final NotificationService _notifications;

  static const formatVersion = 1;

  Future<bool> exportJson() async {
    final items = await _db.allItems();
    final payload = {
      'app': 'coffre',
      'format': formatVersion,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'items': items.map(_toJson).toList(),
    };
    final bytes = utf8.encode(
      const JsonEncoder.withIndent('  ').convert(payload),
    );
    return _system.saveDocument(
      name: 'coffre-sauvegarde-${formatFileStamp(DateTime.now())}.json',
      mimeType: 'application/json',
      bytes: Uint8List.fromList(bytes),
    );
  }

  Future<bool> exportCsv() async {
    final items = await _db.allItems();
    // Séparateur « ; » et BOM UTF-8 : ouverture directe et accents corrects
    // dans Excel configuré en français (Belgique).
    final buffer = StringBuffer('﻿')
      ..writeln(
        'id;type;statut;priorite;contexte;contenu;texte_origine;tags;rappel;repetition;pre_alerte;inbox;cree_le;modifie_le;fait_le',
      );
    for (final i in items) {
      buffer.writeln(
        [
          '${i.id}',
          i.kind.label,
          i.status.label,
          i.priority.label,
          i.context ?? '',
          _csv(i.content),
          _csv(i.raw ?? ''),
          _csv(i.tags.join(', ')),
          _date(i.remindAt),
          i.recurrence == Recurrence.none ? '' : i.recurrence.label,
          i.preAlert ? 'oui' : 'non',
          i.inbox ? 'oui' : 'non',
          _date(i.createdAt),
          _date(i.updatedAt),
          _date(i.doneAt),
        ].join(';'),
      );
    }
    return _system.saveDocument(
      name: 'coffre-export-${formatFileStamp(DateTime.now())}.csv',
      mimeType: 'text/csv',
      bytes: Uint8List.fromList(utf8.encode(buffer.toString())),
    );
  }

  /// Retourne null si l'utilisateur annule le sélecteur de fichier.
  Future<ImportReport?> importJson() async {
    final bytes = await _system.openDocument(
      mimeTypes: const [
        'application/json',
        'text/plain',
        'application/octet-stream',
      ],
    );
    if (bytes == null) return null;
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map ||
        decoded['app'] != 'coffre' ||
        decoded['items'] is! List) {
      throw const FormatException(
        'Ce fichier n\'est pas une sauvegarde Coffre.',
      );
    }
    final raw = (decoded['items'] as List).whereType<Map>().toList();
    final entries = raw.map(_fromJson).whereType<ItemsCompanion>().toList();
    final added = await _db.importItems(entries);
    for (final item in added) {
      await _notifications.schedule(item);
    }
    return ImportReport(added.length, raw.length - added.length);
  }

  Map<String, Object?> _toJson(Item i) => {
    'id': i.id,
    'kind': i.kind.name,
    'status': i.status.name,
    'priority': i.priority.name,
    'content': i.content,
    'raw': i.raw,
    'context': i.context,
    'tags': i.tags,
    'remindAt': i.remindAt?.toUtc().toIso8601String(),
    'preAlert': i.preAlert,
    'recurrence': i.recurrence.name,
    'notionUrl': i.notionUrl,
    'inbox': i.inbox,
    'createdAt': i.createdAt.toUtc().toIso8601String(),
    'updatedAt': i.updatedAt.toUtc().toIso8601String(),
    'doneAt': i.doneAt?.toUtc().toIso8601String(),
  };

  ItemsCompanion? _fromJson(Map raw) {
    final content = raw['content'];
    final kind = ItemKind.values.asNameMap()[raw['kind']];
    final created = DateTime.tryParse('${raw['createdAt']}')?.toLocal();
    if (content is! String ||
        content.trim().isEmpty ||
        kind == null ||
        created == null) {
      return null;
    }
    final tags = (raw['tags'] is List)
        ? (raw['tags'] as List).whereType<String>().toList()
        : <String>[];
    DateTime? date(String key) => DateTime.tryParse('${raw[key]}')?.toLocal();
    String? text(String key) =>
        raw[key] is String && (raw[key] as String).trim().isNotEmpty
        ? raw[key] as String
        : null;
    final context = text('context');
    return ItemsCompanion.insert(
      kind: kind,
      content: content,
      status: Value(
        ItemStatus.values.asNameMap()[raw['status']] ?? ItemStatus.todo,
      ),
      priority: Value(
        ItemPriority.values.asNameMap()[raw['priority']] ?? ItemPriority.normal,
      ),
      tags: Value(tags),
      remindAt: Value(date('remindAt')),
      raw: Value(text('raw')),
      context: Value(context),
      preAlert: Value(raw['preAlert'] == true),
      recurrence: Value(
        Recurrence.values.asNameMap()[raw['recurrence']] ?? Recurrence.none,
      ),
      notionUrl: Value(text('notionUrl')),
      inbox: Value(raw['inbox'] != false),
      searchText: Value(buildSearchText(content, [...tags, ?context])),
      createdAt: created,
      updatedAt: date('updatedAt') ?? created,
      doneAt: Value(date('doneAt')),
    );
  }

  static String _csv(String value) => '"${value.replaceAll('"', '""')}"';

  static String _date(DateTime? d) => d == null
      ? ''
      : d.toLocal().toIso8601String().substring(0, 16).replaceFirst('T', ' ');
}
