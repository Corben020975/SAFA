import 'package:coffre/quick_capture.dart';
import 'package:coffre/core/app_services.dart';
import 'package:coffre/data/app_settings.dart';
import 'package:coffre/data/backup_service.dart';
import 'package:coffre/data/database.dart';
import 'package:coffre/services/ai/ai_assistant.dart';
import 'package:coffre/services/ai/claude_client.dart';
import 'package:coffre/services/ai/gemini_client.dart';
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

  testWidgets('Ajouter à Coffre : panneau, rappel du mail, tag source', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    const channel = MethodChannel('coffre/quick');
    var closed = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'close') closed = true;
          return null;
        });

    final db = AppDatabase(NativeDatabase.memory());
    final settings = AppSettings(db);
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
    const mail =
        'Pourriez-vous m’envoyer le rapport d’activité d’ici la fin de la semaine ?';
    await tester.pumpWidget(
      AppScope(
        services: services,
        child: MaterialApp(
          home: QuickCaptureSheet(
            text: mail,
            source: 'outlook',
            channel: channel,
          ),
        ),
      ),
    );
    await settle(tester);
    expect(find.text('Ajouter à Coffre'), findsOneWidget);
    expect(find.textContaining('#outlook'), findsOneWidget);

    await tester.tap(find.text('Enregistrer'));
    await settle(tester);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(seconds: 1));
    await settle(tester);

    final item = (await tester.runAsync(db.allItems))!.single;
    expect(item.tags, ['outlook']);
    expect(item.raw, mail);
    expect(item.remindAt!.weekday, DateTime.friday);
    expect(closed, isTrue);
    await tester.runAsync(db.close);
  });
}
