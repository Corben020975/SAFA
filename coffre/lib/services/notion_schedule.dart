import 'dart:io';
import 'dart:ui';

import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import '../data/app_settings.dart';
import '../data/database.dart';
import '../data/db_opener.dart';
import '../data/enums.dart';
import 'ai/ai_assistant.dart';
import 'ai/claude_client.dart';
import 'ai/gemini_client.dart';
import 'day_focus.dart';
import 'notification_service.dart';
import 'notion_import.dart';
import 'notion_service.dart';
import 'secret_store.dart';

/// Rendez-vous quotidiens, même app fermée (AlarmManager) : à 7 h 30
/// « Tes 3 priorités » ; à 7 h 30 et 13 h, import Notion si activé.
const kNotionSyncTimes = [(7, 30), (13, 0)];
const _alarmId = 7301;

/// Prochain créneau strictement après [now].
DateTime nextNotionSync(DateTime now) {
  for (var day = 0; day < 2; day++) {
    for (final (hour, minute) in kNotionSyncTimes) {
      final at = DateTime(now.year, now.month, now.day + day, hour, minute);
      if (at.isAfter(now)) return at;
    }
  }
  final (hour, minute) = kNotionSyncTimes.first;
  return DateTime(now.year, now.month, now.day + 1, hour, minute);
}

bool _notionOn(AppSettings s) => s.notionScheduled && s.notionImport != null;

/// (Re)programme le prochain créneau, ou l'annule si tout est désactivé.
Future<void> scheduleNotionSync(AppSettings settings) async {
  if (!Platform.isAndroid) return;
  try {
    if (!settings.morningFocus && !_notionOn(settings)) {
      await AndroidAlarmManager.cancel(_alarmId);
      return;
    }
    await AndroidAlarmManager.oneShotAt(
      nextNotionSync(DateTime.now()),
      _alarmId,
      notionSyncCallback,
      exact: true,
      wakeup: true,
      allowWhileIdle: true,
      rescheduleOnReboot: true,
    );
  } catch (_) {
    // L'import à l'ouverture de l'app reste le filet de sécurité.
  }
}

/// Exécuté par Android à 7 h 30 et 13 h, dans un moteur Flutter sans écran.
@pragma('vm:entry-point')
Future<void> notionSyncCallback() async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  await initializeDateFormatting('fr');
  Intl.defaultLocale = 'fr';
  final db = await openDatabaseForBackground();
  if (db == null) return;
  final settings = AppSettings(db);
  try {
    await settings.load();
    final now = DateTime.now();
    final morning = now.hour < 11;
    final target = NotionTarget.fromMap(settings.notionImport);
    final notionOn = settings.notionScheduled && target != null;
    if (!notionOn && !(morning && settings.morningFocus)) return;
    final secrets = SecretStore();
    final notifications = NotificationService();
    await notifications.init();

    NotionImportResult? result;
    if (notionOn) {
      try {
        result = await importNotionTasks(
          db,
          NotionService(() => secrets.read(SecretStore.notionKey)),
          target,
          context: settings.notionImportContext,
        );
        for (final item in [...result.added, ...result.closed]) {
          await notifications.schedule(item);
        }
      } catch (_) {
        result = null; // hors ligne : on réessaiera au prochain créneau
      }
    }

    String? brief;
    if (settings.aiDigest && settings.consentFor(settings.aiProvider)) {
      final ai = AiAssistant(
        ClaudeClient(() => secrets.read(SecretStore.aiKey)),
        GeminiClient(() => secrets.read(SecretStore.geminiKey)),
        settings,
      );
      final open = (await db.allItems())
          .where((i) => i.status != ItemStatus.done)
          .toList();
      try {
        if (open.isNotEmpty) brief = await ai.digest(open, DateTime.now());
      } catch (_) {
        brief = null;
      }
    }

    final added = result?.added ?? const [];
    String line(Item i) => i.content.split('\n').first;

    // 7 h 30 : « Tes 3 priorités », choisies pour la journée.
    if (morning && settings.morningFocus) {
      final open = (await db.allItems())
          .where((i) => i.status != ItemStatus.done)
          .toList();
      final focus = await DayFocus.ensure(settings, open, now);
      if (focus.isNotEmpty || brief != null || added.isNotEmpty) {
        await notifications.showDigest(
          focus.length == 1
              ? 'Ta priorité du jour'
              : 'Tes ${focus.length} priorités du jour',
          [
            ?brief,
            if (focus.isNotEmpty)
              [
                for (var k = 0; k < focus.length; k++)
                  '${k + 1}. ${line(focus[k])}',
              ].join('\n'),
            if (added.isNotEmpty)
              added.length == 1
                  ? '+ 1 nouvelle tâche depuis Notion'
                  : '+ ${added.length} nouvelles tâches depuis Notion',
          ].join('\n\n'),
        );
      }
      return;
    }

    if (added.isEmpty && brief == null) return;
    final titles = added.take(4).map((i) => '• ${line(i)}').join('\n');
    await notifications.showDigest(
      added.isEmpty
          ? 'Ton point Coffre'
          : added.length == 1
          ? '1 nouvelle tâche depuis Notion'
          : '${added.length} nouvelles tâches depuis Notion',
      [?brief, if (titles.isNotEmpty) titles].join('\n\n'),
    );
  } finally {
    await scheduleNotionSync(settings);
    await db.close();
  }
}
