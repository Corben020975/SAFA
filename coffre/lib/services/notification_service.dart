import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../data/database.dart';
import '../data/enums.dart';
import 'notification_actions.dart';

enum ScheduleOutcome { none, exact, inexact }

class NotificationService {
  /// Un canal Android est figé après création (son, importance) :
  /// pour le modifier, changer l'identifiant (v2…).
  static const channelId = 'coffre_rappels_v1';
  static const _channelName = 'Rappels';
  static const _channelDescription = 'Rappels de tâches, idées et notes';
  static const testNotificationId = 2000000000;
  static const _icon = 'ic_stat_coffre';

  static const snoozeActions = {'snooze_5': 5, 'snooze_15': 15, 'snooze_60': 60};

  final _plugin = FlutterLocalNotificationsPlugin();

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  Future<void> init({
    void Function(NotificationResponse response)? onForegroundResponse,
  }) async {
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings(_icon),
      ),
      onDidReceiveNotificationResponse: onForegroundResponse,
      onDidReceiveBackgroundNotificationResponse: notificationBackgroundEntry,
    );
    await _android?.createNotificationChannel(
      const AndroidNotificationChannel(
        channelId,
        _channelName,
        description: _channelDescription,
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        showBadge: true,
      ),
    );
  }

  /// Programme (ou reprogramme) le rappel de l'élément. Annule s'il n'y a
  /// plus de rappel futur. Retombe sur une alarme inexacte si Android refuse
  /// les alarmes exactes, plutôt que de perdre le rappel.
  Future<ScheduleOutcome> schedule(Item item) async {
    final at = item.remindAt;
    if (at == null ||
        item.status == ItemStatus.done ||
        !at.isAfter(DateTime.now())) {
      await cancel(item.id);
      return ScheduleOutcome.none;
    }
    // Instant absolu en UTC : pas de dépendance au nom de fuseau du téléphone
    // (source de bugs sur certains Samsung), et l'heure reste juste après
    // un changement d'heure été/hiver.
    final when = tz.TZDateTime.from(at.toUtc(), tz.UTC);
    try {
      await _zoned(item, when, AndroidScheduleMode.exactAllowWhileIdle);
      return ScheduleOutcome.exact;
    } on PlatformException catch (e) {
      if (e.code != 'exact_alarms_not_permitted') rethrow;
      await _zoned(item, when, AndroidScheduleMode.inexactAllowWhileIdle);
      return ScheduleOutcome.inexact;
    }
  }

  Future<void> cancel(int id) => _plugin.cancel(id: id);

  /// La base est la source de vérité : au démarrage, on réaligne les alarmes
  /// (éléments supprimés, rappels modifiés hors ligne, mise à jour de l'app…).
  Future<void> resync(List<Item> upcoming) async {
    final wanted = {for (final item in upcoming) item.id};
    try {
      final pending = await _plugin.pendingNotificationRequests();
      for (final request in pending) {
        if (!wanted.contains(request.id) && request.id != testNotificationId) {
          await _plugin.cancel(id: request.id);
        }
      }
    } catch (_) {}
    for (final item in upcoming) {
      try {
        await schedule(item);
      } catch (_) {}
    }
  }

  Future<ScheduleOutcome> scheduleTest(Duration delay) async {
    final when = tz.TZDateTime.from(
      DateTime.now().toUtc().add(delay),
      tz.UTC,
    );
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        _channelName,
        channelDescription: _channelDescription,
        icon: _icon,
        importance: Importance.max,
        priority: Priority.high,
        category: AndroidNotificationCategory.reminder,
      ),
    );
    Future<void> run(AndroidScheduleMode mode) => _plugin.zonedSchedule(
      id: testNotificationId,
      scheduledDate: when,
      notificationDetails: details,
      androidScheduleMode: mode,
      title: 'Test Coffre',
      body: 'Les rappels fonctionnent. Tu peux fermer cette notification.',
    );
    try {
      await run(AndroidScheduleMode.exactAllowWhileIdle);
      return ScheduleOutcome.exact;
    } on PlatformException catch (e) {
      if (e.code != 'exact_alarms_not_permitted') rethrow;
      await run(AndroidScheduleMode.inexactAllowWhileIdle);
      return ScheduleOutcome.inexact;
    }
  }

  Future<bool> areEnabled() async =>
      await _android?.areNotificationsEnabled() ?? true;

  Future<bool> requestPermission() async =>
      await _android?.requestNotificationsPermission() ?? false;

  Future<bool> canScheduleExact() async =>
      await _android?.canScheduleExactNotifications() ?? true;

  Future<bool> requestExactAlarms() async =>
      await _android?.requestExactAlarmsPermission() ?? false;

  Future<NotificationAppLaunchDetails?> launchDetails() =>
      _plugin.getNotificationAppLaunchDetails();

  Future<void> _zoned(
    Item item,
    tz.TZDateTime when,
    AndroidScheduleMode mode,
  ) {
    final lines = item.content.trim().split('\n');
    var title = lines.first.trim();
    if (title.length > 80) title = '${title.substring(0, 77)}…';
    final rest = lines.skip(1).join('\n').trim();
    final body = rest.isEmpty ? '${item.kind.label} · touche pour ouvrir' : rest;

    return _plugin.zonedSchedule(
      id: item.id,
      scheduledDate: when,
      androidScheduleMode: mode,
      title: title,
      body: body,
      payload: '${item.id}',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          _channelName,
          channelDescription: _channelDescription,
          icon: _icon,
          importance: Importance.max,
          priority: Priority.high,
          category: AndroidNotificationCategory.reminder,
          // Contenu masqué sur l'écran verrouillé si l'option système
          // « masquer le contenu sensible » est active.
          visibility: NotificationVisibility.private,
          color: const Color(0xFF2E7D6B),
          subText: item.priority == ItemPriority.high
              ? '${item.kind.label} · priorité haute'
              : item.kind.label,
          styleInformation: BigTextStyleInformation(body),
          when: item.remindAt!.millisecondsSinceEpoch,
          // Android affiche au maximum 3 boutons : les 3 reports demandés.
          actions: const [
            AndroidNotificationAction('snooze_5', '5 min'),
            AndroidNotificationAction('snooze_15', '15 min'),
            AndroidNotificationAction('snooze_60', '1 h'),
          ],
        ),
      ),
    );
  }
}
