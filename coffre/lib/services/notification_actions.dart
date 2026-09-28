import 'dart:ui';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../data/db_opener.dart';
import 'notification_service.dart';

/// Point d'entrée exécuté par Android dans un isolate séparé quand on touche
/// « 5 min / 15 min / 1 h » sur une notification, même app fermée.
/// Doit rester une fonction de premier niveau annotée vm:entry-point.
@pragma('vm:entry-point')
Future<void> notificationBackgroundEntry(NotificationResponse response) async {
  // Les plugins Dart (path_provider…) ne sont pas enregistrés d'office
  // dans cet isolate.
  DartPluginRegistrant.ensureInitialized();
  await handleSnoozeAction(response);
}

Future<void> handleSnoozeAction(NotificationResponse response) async {
  final minutes = NotificationService.snoozeActions[response.actionId];
  final id = int.tryParse(response.payload ?? '');
  if (minutes == null || id == null) return;

  final db = await openDatabaseForBackground();
  if (db == null) return;
  try {
    final item = await db.snooze(id, Duration(minutes: minutes));
    if (item != null) {
      final notifications = NotificationService();
      await notifications.init();
      await notifications.schedule(item);
    }
  } finally {
    await db.close();
  }
}
