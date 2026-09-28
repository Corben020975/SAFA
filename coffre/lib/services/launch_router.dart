import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../data/enums.dart';
import '../ui/screens/capture_screen.dart';
import 'notification_service.dart';
import 'system_channel.dart';

/// Ouvre le bon écran quand l'app est lancée par une notification
/// (→ Détail) ou par le widget d'accueil (→ Capture, éventuellement en voix).
class LaunchRouter {
  LaunchRouter(this.navigatorKey, this._system, this._notifications) {
    _system.onLaunchAction = _openUri;
  }

  final GlobalKey<NavigatorState> navigatorKey;
  final SystemChannel _system;
  final NotificationService _notifications;

  /// À appeler une fois, après la première image.
  Future<void> handleColdStart() async {
    final details = await _notifications.launchDetails();
    final response = details?.notificationResponse;
    if (details?.didNotificationLaunchApp == true && response != null) {
      onNotificationResponse(response);
      return;
    }
    final uri = await _system.takeLaunchAction();
    if (uri != null) _openUri(uri);
  }

  /// Toucher le corps d'une notification pendant que l'app tourne.
  void onNotificationResponse(NotificationResponse response) {
    if (response.notificationResponseType !=
        NotificationResponseType.selectedNotification) {
      return;
    }
    final id = int.tryParse(response.payload ?? '');
    if (id != null && id != NotificationService.testNotificationId) {
      navigatorKey.currentState?.pushNamed('/item', arguments: id);
    }
  }

  // coffre://capture?kind=task&voice=1
  void _openUri(String raw) {
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.host != 'capture') return;
    navigatorKey.currentState?.pushNamed(
      '/capture',
      arguments: CaptureArgs(
        kind: ItemKind.values.asNameMap()[uri.queryParameters['kind']],
        startWithVoice: uri.queryParameters['voice'] == '1',
      ),
    );
  }
}
