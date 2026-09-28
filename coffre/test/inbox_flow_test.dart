import 'package:coffre/app.dart';
import 'package:coffre/core/app_services.dart';
import 'package:coffre/data/app_settings.dart';
import 'package:coffre/data/backup_service.dart';
import 'package:coffre/data/database.dart';
import 'package:coffre/data/enums.dart';
import 'package:coffre/services/launch_router.dart';
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
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
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
      (call) async => call.method == 'isIgnoringBatteryOptimizations' ? true : null,
    );
  });

  /// Alterne temps réel (requêtes SQLite) et temps simulé (timers Flutter).
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    }
    await tester.pump();
  }

  testWidgets('Inbox : affichage, filtre, marquer fait', (tester) async {
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
      encryptionActive: false,
    );

    await tester.runAsync(() async {
      await db.createItem(
        kind: ItemKind.task,
        content: 'Appeler le médecin',
        priority: ItemPriority.high,
        remindAt: DateTime.now().add(const Duration(days: 1)),
      );
      await db.createItem(kind: ItemKind.idea, content: 'Idée de prompt');
    });

    await tester.pumpWidget(
      CoffreApp(
        services: services,
        router: LaunchRouter(GlobalKey<NavigatorState>(), system, notifications),
      ),
    );
    await settle(tester);

    expect(find.text('Appeler le médecin'), findsOneWidget);
    expect(find.text('Idée de prompt'), findsOneWidget);
    expect(find.text('Inbox · 2'), findsOneWidget);

    // Filtre « Idées » : la tâche disparaît.
    await tester.tap(find.text('Idées · 1'));
    await settle(tester);
    expect(find.text('Appeler le médecin'), findsNothing);

    // Retour Inbox, puis « fait » d'un tap sur le rond.
    await tester.tap(find.text('Inbox · 2'));
    await settle(tester);
    await tester.tap(find.byTooltip('Marquer fait').first);
    await settle(tester);

    expect(find.text('Appeler le médecin'), findsNothing);
    expect(find.text('Marqué fait'), findsOneWidget);
    // Rappel annulé côté Android puisque la tâche est faite.
    expect(calls, contains('cancel'));

    // Puce « Fait » en bout de barre de filtres : on la fait défiler.
    await tester.ensureVisible(find.text('Fait'));
    await tester.tap(find.text('Fait'));
    await settle(tester);
    expect(find.text('Appeler le médecin'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await settle(tester);
    await tester.runAsync(db.close);
  });
}
