import 'package:flutter/widgets.dart';

import '../data/app_settings.dart';
import '../data/backup_service.dart';
import '../data/database.dart';
import '../services/ai/ai_assistant.dart';
import '../services/ai/nano_client.dart';
import '../services/notification_service.dart';
import '../services/notion_service.dart';
import '../services/secret_store.dart';
import '../services/speech_service.dart';
import '../services/system_channel.dart';

/// Services partagés, créés une fois dans main(). Pas de framework d'état :
/// flux Drift + ChangeNotifier suffisent pour 3 écrans.
class AppServices {
  AppServices({
    required this.db,
    required this.settings,
    required this.notifications,
    required this.speech,
    required this.system,
    required this.backup,
    required this.secrets,
    required this.ai,
    required this.nano,
    required this.notion,
    required this.encryptionActive,
    this.setAsideDbFile,
  });

  final AppDatabase db;
  final AppSettings settings;
  final NotificationService notifications;
  final SpeechService speech;
  final SystemChannel system;
  final BackupService backup;
  final SecretStore secrets;
  final AiAssistant ai;
  final NanoClient nano;
  final NotionService notion;
  final bool encryptionActive;
  final String? setAsideDbFile;
}

class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.services, required super.child});
  final AppServices services;

  static AppServices of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()!.services;

  @override
  bool updateShouldNotify(AppScope oldWidget) => services != oldWidget.services;
}
