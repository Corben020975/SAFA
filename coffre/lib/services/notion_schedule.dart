import 'dart:io';
import 'dart:ui';

import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import '../data/app_settings.dart';
import '../data/db_opener.dart';
import '../data/enums.dart';
import 'ai/ai_assistant.dart';
import 'ai/claude_client.dart';
import 'ai/gemini_client.dart';
import 'notification_service.dart';
import 'notion_import.dart';
import 'notion_service.dart';
import 'secret_store.dart';

/// Import Notion programmé à heures fixes, même app fermée (AlarmManager).
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

/// (Re)programme le prochain import, ou l'annule si désactivé.
Future<void> scheduleNotionSync(AppSettings settings) async {
  if (!Platform.isAndroid) return;
  try {
    if (!settings.notionScheduled || settings.notionImport == null) {
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
    final target = NotionTarget.fromMap(settings.notionImport);
    if (!settings.notionScheduled || target == null) return;
    final secrets = SecretStore();
    final notifications = NotificationService();
    await notifications.init();

    NotionImportResult? result;
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
    if (added.isEmpty && brief == null) return;
    final titles = added
        .take(4)
        .map((i) => '• ${i.content.split('\n').first}')
        .join('\n');
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
