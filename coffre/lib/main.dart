import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'app.dart';
import 'core/app_services.dart';
import 'data/app_settings.dart';
import 'data/backup_service.dart';
import 'data/db_opener.dart';
import 'services/launch_router.dart';
import 'services/notification_service.dart';
import 'services/speech_service.dart';
import 'services/system_channel.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Affichage bord à bord : l'app dessine sous les barres système.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  LicenseRegistry.addLicense(() async* {
    final text = await rootBundle.loadString('assets/fonts/OFL-Fraunces.txt');
    yield LicenseEntryWithLineBreaks(['Fraunces'], text);
  });
  await initializeDateFormatting('fr');
  Intl.defaultLocale = 'fr';

  try {
    final opened = await openDatabaseForUi();
    final db = opened.db;
    final settings = AppSettings(db);
    await settings.load();

    final system = SystemChannel();
    final notifications = NotificationService();
    final navigatorKey = GlobalKey<NavigatorState>();
    final router = LaunchRouter(navigatorKey, system, notifications);
    await notifications.init(
      onForegroundResponse: router.onNotificationResponse,
    );

    final services = AppServices(
      db: db,
      settings: settings,
      notifications: notifications,
      speech: SpeechService(),
      system: system,
      backup: BackupService(db, system, notifications),
      encryptionActive: await isEncryptionAvailable(db),
      setAsideDbFile: opened.setAsideFile,
    );

    // La base fait foi : on réaligne les alarmes sans bloquer l'affichage.
    unawaited(db.pendingReminders().then(notifications.resync));

    runApp(CoffreApp(services: services, router: router));
  } catch (error, stack) {
    debugPrint('Démarrage impossible : $error\n$stack');
    runApp(_StartupErrorApp(error: '$error'));
  }
}

/// Plutôt qu'un écran blanc : un message lisible à recopier.
class _StartupErrorApp extends StatelessWidget {
  const _StartupErrorApp({required this.error});
  final String error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ListView(
              children: [
                const Text(
                  'Coffre n\'a pas pu démarrer',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Tes données ne sont pas effacées. Redémarre le téléphone puis '
                  'rouvre l\'app. Si le problème continue, note le message ci-dessous.',
                ),
                const SizedBox(height: 16),
                SelectableText(error),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
