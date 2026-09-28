import 'package:coffre/app.dart';
import 'package:coffre/core/app_services.dart';
import 'package:coffre/data/app_settings.dart';
import 'package:coffre/data/backup_service.dart';
import 'package:coffre/data/database.dart';
import 'package:coffre/services/ai/ai_assistant.dart';
import 'package:coffre/services/ai/claude_client.dart';
import 'package:coffre/services/ai/gemini_client.dart';
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

  testWidgets('Réglages IA : Gemini par défaut, bascule vers Claude', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final db = AppDatabase(NativeDatabase.memory());
    final settings = AppSettings(db)..onboardingDone = true;
    final system = SystemChannel();
    final notifications = NotificationService();
    final services = AppServices(
      db: db,
      settings: settings,
      notifications: notifications,
      speech: SpeechService(),
      system: system,
      backup: BackupService(db, system, notifications),
      secrets: SecretStore(),
      ai: AiAssistant(
        ClaudeClient(() async => null),
        GeminiClient(() async => null),
        settings,
      ),
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
      find.text('Clé API Gemini'),
      200,
      scrollable: list,
    );
    await settle(tester);
    expect(settings.aiProvider, AiProvider.gemini);
    expect(find.text('Gemini (gratuit)'), findsOneWidget);
    expect(find.textContaining('offre gratuite avec limites'), findsOneWidget);

    await tester.ensureVisible(find.text('Claude (payant)'));
    await settle(tester);
    await tester.tap(find.text('Claude (payant)'));
    await settle(tester);
    expect(settings.aiProvider, AiProvider.claude);
    expect(find.text('Clé API Claude'), findsOneWidget);
    expect(find.text('Clé API Gemini'), findsNothing);
    await tester.runAsync(db.close);
  });
}
