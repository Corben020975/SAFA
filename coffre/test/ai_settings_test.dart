import 'dart:async';

import 'package:coffre/app.dart';
import 'package:coffre/core/app_services.dart';
import 'package:coffre/data/app_settings.dart';
import 'package:coffre/data/backup_service.dart';
import 'package:coffre/data/database.dart';
import 'package:coffre/services/ai/ai_assistant.dart';
import 'package:coffre/services/ai/claude_client.dart';
import 'package:coffre/services/ai/nano_client.dart';
import 'package:coffre/services/launch_router.dart';
import 'package:coffre/services/notion_service.dart';
import 'package:coffre/services/secret_store.dart';
import 'package:coffre/services/notification_service.dart';
import 'package:coffre/services/speech_service.dart';
import 'package:coffre/services/system_channel.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  final calls = <String>[];

  setUp(() async {
    calls.clear();
    await initializeDateFormatting('fr');
    // En test, l'implémentation Android du plugin n'est pas enregistrée d'office.
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    // Plugin de notifications simulé : tout est autorisé.
    messenger.setMockMethodCallHandler(
      const MethodChannel('dexterous.com/flutter/local_notifications'),
      (call) async {
        calls.add(call.method);
        return switch (call.method) {
          'areNotificationsEnabled' || 'canScheduleExactNotifications' => true,
          'pendingNotificationRequests' => <Object?>[],
          _ => null,
        };
      },
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('coffre/system'),
      (call) async =>
          call.method == 'isIgnoringBatteryOptimizations' ? true : null,
    );
  });

  /// Alterne temps réel (requêtes SQLite) et temps simulé (timers Flutter).
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
    }
    await tester.pump();
  }

  testWidgets('Réglages IA : moteur, téléchargement de Gemini Nano', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    // Pont Android simulé : modèle à télécharger, téléchargement piloté.
    var status = 'downloadable';
    final download = Completer<bool>();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('coffre/nano'),
      (call) async => switch (call.method) {
        'status' => {'status': status},
        'download' => download.future,
        _ => null,
      },
    );

    final db = AppDatabase(NativeDatabase.memory());
    final settings = AppSettings(db)..onboardingDone = true;
    final system = SystemChannel();
    final notifications = NotificationService();
    final nano = NanoClient();
    final services = AppServices(
      db: db,
      settings: settings,
      notifications: notifications,
      speech: SpeechService(),
      system: system,
      backup: BackupService(db, system, notifications),
      secrets: SecretStore(),
      ai: AiAssistant(ClaudeClient(() async => null), nano, settings),
      nano: nano,
      notion: NotionService(() async => null),
      encryptionActive: false,
    );
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      CoffreApp(
        services: services,
        router: LaunchRouter(key, system, notifications),
      ),
    );
    await settle(tester);
    key.currentState!.pushNamed('/settings');
    await settle(tester);
    final list = find.byType(Scrollable).hitTestable().first;
    await tester.scrollUntilVisible(
      find.text('Gemini Nano'),
      200,
      scrollable: list,
    );
    await settle(tester);
    expect(find.text('Modèle à télécharger (1 à 2 Go)'), findsOneWidget);

    // Bascule vers Claude puis retour : le choix est enregistré.
    await tester.ensureVisible(find.text('Claude en ligne'));
    await settle(tester);
    await tester.tap(find.text('Claude en ligne'));
    await settle(tester);
    expect(settings.aiProvider, AiProvider.claude);
    await tester.scrollUntilVisible(
      find.text('Clé API Claude'),
      200,
      scrollable: list,
    );
    await tester.ensureVisible(find.text('Sur le téléphone'));
    await settle(tester);
    await tester.tap(find.text('Sur le téléphone'));
    await settle(tester);
    expect(settings.aiProvider, AiProvider.nano);

    // Téléchargement : progression affichée, puis modèle prêt.
    await tester.ensureVisible(find.text('Télécharger'));
    await settle(tester);
    await tester.tap(find.text('Télécharger'));
    await settle(tester);
    expect(find.text('Téléchargement de Gemini Nano'), findsOneWidget);
    await tester.runAsync(
      () => messenger.handlePlatformMessage(
        'coffre/nano',
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('progress', {
            'done': 420000000,
            'total': 1000000000,
          }),
        ),
        (_) {},
      ),
    );
    await settle(tester);
    expect(find.text('42 % · 420 Mo / 1000 Mo'), findsOneWidget);

    status = 'available';
    download.complete(true);
    await settle(tester);
    await settle(tester);
    expect(find.text('Téléchargement de Gemini Nano'), findsNothing);
    expect(find.text('Prêt · fonctionne hors ligne'), findsOneWidget);
    expect(find.text('Tester'), findsOneWidget);
    await tester.runAsync(db.close);
  });
}
