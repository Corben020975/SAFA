import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';

import '../core/app_services.dart';
import '../core/date_labels.dart';
import '../data/database.dart';
import '../data/enums.dart';
import '../services/day_board.dart';
import '../services/notion_import.dart';
import 'theme.dart';
import 'widgets/reminder_field.dart';

/// Actions communes aux vues Jour et Flux, toutes annulables.
class ItemActions {
  static void open(BuildContext context, Item item) =>
      Navigator.of(context).pushNamed('/item', arguments: item.id);

  static Future<void> toggleDone(BuildContext context, Item item) async {
    final s = AppScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final wasDone = item.status == ItemStatus.done;
    final updated = await s.db.setStatus(
      item.id,
      wasDone ? ItemStatus.todo : ItemStatus.done,
    );
    if (updated != null) await s.notifications.schedule(updated);
    // Élément répété : il revient à sa prochaine date au lieu de se clore.
    final repeated =
        !wasDone && updated != null && updated.status != ItemStatus.done;
    if (!wasDone && !repeated && item.notionUrl != null) {
      // Après le délai d'annulation : la page Notion passe aussi à « Fait ».
      unawaited(
        pushDoneToNotion(
          s,
          item.id,
          delay: kUndoDuration + const Duration(seconds: 1),
        ),
      );
    }
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            wasDone
                ? 'Réactivé'
                : repeated && updated.remindAt != null
                ? 'Fait · prochaine fois ${formatReminder(updated.remindAt!)}'
                : 'Fait · ${_short(item)}',
          ),
          persist: false,
          duration: kUndoDuration,
          action: SnackBarAction(
            label: 'Annuler',
            onPressed: () async {
              await s.db.restoreItem(item);
              await s.notifications.schedule(item);
            },
          ),
        ),
      );
  }

  static Future<void> archive(BuildContext context, Item item) async {
    final s = AppScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    await s.db.setInbox(item.id, false);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Classé · retrouvable dans ${item.kind.plural}'),
          persist: false,
          duration: kUndoDuration,
          action: SnackBarAction(
            label: 'Annuler',
            onPressed: () => s.db.setInbox(item.id, true),
          ),
        ),
      );
  }

  /// « Plus tard » : dans 2 h, ce soir, demain matin ou date libre.
  static Future<void> later(BuildContext context, Item item) async {
    final s = AppScope.of(context);
    final p = Palette.of(context);
    final now = DateTime.now();
    final custom = DateTime(0);
    final choice = await showModalBottomSheet<DateTime>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text('Plus tard', style: displayStyle(sheet, 24)),
              ),
              for (final (label, at) in laterChoices(now))
                ListTile(
                  leading: const Icon(Icons.schedule),
                  title: Text(label),
                  subtitle: Text(
                    formatReminder(at),
                    style: TextStyle(color: p.muted),
                  ),
                  onTap: () => Navigator.pop(sheet, at),
                ),
              ListTile(
                leading: const Icon(Icons.edit_calendar_outlined),
                title: const Text('Choisir une date…'),
                onTap: () => Navigator.pop(sheet, custom),
              ),
            ],
          ),
        ),
      ),
    );
    if (choice == null || !context.mounted) return;
    final at = choice == custom
        ? await pickReminderDateTime(context, item.remindAt)
        : choice;
    if (at == null || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final updated = await s.db.setReminder(item.id, at);
    if (updated != null) await s.notifications.schedule(updated);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Rappel : ${formatReminder(at)}'),
          persist: false,
          duration: kUndoDuration,
          action: SnackBarAction(
            label: 'Annuler',
            onPressed: () async {
              final restored = await s.db.saveItem(
                (await s.db.getItem(item.id))!
                    .copyWith(remindAt: Value(item.remindAt)),
              );
              await s.notifications.schedule(restored);
            },
          ),
        ),
      );
  }

  static String _short(Item item) {
    final title = item.content.split('\n').first;
    return title.length > 40 ? '${title.substring(0, 38)}…' : title;
  }
}

/// « Tâche · Santé »
String itemMeta(Item item) => [item.kind.label, ?item.context].join(' · ');

/// « Demain 09:00 », « En retard · Hier 09:00 », « Lundi 09:00 · chaque semaine ».
String? itemWhen(Item item, DateTime now) {
  final at = item.remindAt;
  if (at == null) return null;
  final overdue = item.status != ItemStatus.done && at.isBefore(now);
  final label = overdue
      ? 'En retard · ${formatReminder(at, now: now)}'
      : formatReminder(at, now: now);
  return item.recurrence == Recurrence.none
      ? label
      : '$label · ${item.recurrence.short}';
}
