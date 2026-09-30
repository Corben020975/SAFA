import '../core/app_services.dart';
import '../data/database.dart';
import '../data/enums.dart';
import 'notion_service.dart';

class NotionImportResult {
  const NotionImportResult(this.added, this.existing, this.done, this.closed);
  final List<Item> added;
  final int existing;
  final int done;

  /// Éléments de Coffre fermés parce que la page est « Fait » dans Notion.
  final List<Item> closed;
}

/// Importe les tâches non terminées d'une base Notion (Grokbot, etc.).
/// Le lien de la page évite les doublons ; une page passée à « Fait » dans
/// Notion ferme l'élément correspondant dans Coffre.
Future<NotionImportResult> importNotionTasks(
  AppDatabase db,
  NotionService notion,
  NotionTarget target, {
  String? context,
}) async {
  final tasks = await notion.fetchTasks(target);
  final known = await db.notionUrls();
  final added = <Item>[];
  final closed = <Item>[];
  var existing = 0, done = 0;
  for (final task in tasks) {
    if (known.contains(task.url)) {
      existing++;
      if (task.done) {
        final item = await db.itemByNotionUrl(task.url);
        if (item != null && item.status != ItemStatus.done) {
          final updated = await db.setStatus(item.id, ItemStatus.done);
          if (updated != null) closed.add(updated);
        }
      }
      continue;
    }
    if (task.done) {
      done++;
      continue;
    }
    String? body;
    if (task.id != null) {
      try {
        body = await notion.pageText(task.id!);
      } on NotionException {
        body = null; // le titre et les notes suffisent
      }
    }
    final content = [
      task.title,
      ?task.note,
      if (body != null && body != task.note) body,
    ].join('\n');
    added.add(
      await db.createItem(
        kind: ItemKind.task,
        content: content,
        priority: task.priority,
        tags: ['notion', ...task.tags],
        remindAt: task.due,
        status: task.doing ? ItemStatus.doing : ItemStatus.todo,
        context: context,
        notionUrl: task.url,
      ),
    );
    known.add(task.url);
  }
  return NotionImportResult(added, existing, done, closed);
}

/// Import automatique à l'ouverture (au plus toutes les 2 minutes).
class NotionAutoImport {
  NotionAutoImport(this._s);
  final AppServices _s;
  DateTime? _last;
  bool _running = false;

  Future<NotionImportResult?> run() async {
    final settings = _s.settings;
    final target = NotionTarget.fromMap(settings.notionImport);
    final now = DateTime.now();
    if (!settings.notionAutoImport || target == null || _running) return null;
    if (_last != null && now.difference(_last!) < const Duration(minutes: 2)) {
      return null;
    }
    _running = true;
    _last = now;
    try {
      if (!await _s.notion.configured) return null;
      final result = await importNotionTasks(
        _s.db,
        _s.notion,
        target,
        context: settings.notionImportContext,
      );
      for (final item in [...result.added, ...result.closed]) {
        await _s.notifications.schedule(item);
      }
      return result;
    } catch (_) {
      return null; // hors ligne, jeton retiré… on réessaiera au prochain retour
    } finally {
      _running = false;
    }
  }
}

/// Coffre → Notion : après le délai d'annulation, si l'élément est toujours
/// « Fait », la page Notion passe aussi à « Fait ».
Future<void> pushDoneToNotion(
  AppServices s,
  int itemId, {
  Duration delay = Duration.zero,
}) async {
  if (!s.settings.notionSyncDone) return;
  if (delay > Duration.zero) await Future<void>.delayed(delay);
  final item = await s.db.getItem(itemId);
  final url = item?.notionUrl;
  if (item == null || url == null || item.status != ItemStatus.done) return;
  try {
    await s.notion.markDone(url);
  } catch (_) {
    // Notion injoignable : la page restera ouverte, sans bloquer Coffre.
  }
}
