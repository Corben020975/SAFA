import '../data/database.dart';
import '../data/enums.dart';
import 'notion_service.dart';

class NotionImportResult {
  const NotionImportResult(this.added, this.existing, this.done);
  final List<Item> added;
  final int existing;
  final int done;
}

/// Importe les tâches non terminées d'une base Notion. Import ponctuel, pas
/// de synchronisation : le lien de la page évite les doublons.
Future<NotionImportResult> importNotionTasks(
  AppDatabase db,
  NotionService notion,
  NotionTarget target,
) async {
  final tasks = await notion.fetchTasks(target);
  final known = await db.notionUrls();
  final added = <Item>[];
  var existing = 0, done = 0;
  for (final task in tasks) {
    if (task.done) {
      done++;
    } else if (known.contains(task.url)) {
      existing++;
    } else {
      added.add(
        await db.createItem(
          kind: ItemKind.task,
          content: task.note == null
              ? task.title
              : '${task.title}\n${task.note}',
          priority: task.priority,
          tags: const ['notion'],
          remindAt: task.due,
          status: task.doing ? ItemStatus.doing : ItemStatus.todo,
          inbox: false,
          notionUrl: task.url,
        ),
      );
      known.add(task.url);
    }
  }
  return NotionImportResult(added, existing, done);
}
