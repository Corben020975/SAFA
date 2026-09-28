import 'package:coffre/app.dart';
import 'package:coffre/core/app_services.dart';
import 'package:coffre/data/app_settings.dart';
import 'package:coffre/data/backup_service.dart';
import 'package:coffre/data/database.dart';
import 'package:coffre/data/enums.dart';
import 'package:coffre/services/ai/ai_assistant.dart';
import 'package:coffre/services/ai/claude_client.dart';
import 'package:coffre/services/launch_router.dart';
import 'package:coffre/services/notion_service.dart';
import 'package:coffre/services/secret_store.dart';
import 'package:coffre/services/notification_service.dart';
import 'package:coffre/services/speech_service.dart';
import 'package:coffre/services/system_channel.dart';
import 'package:coffre/ui/widgets/item_card.dart';
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

  testWidgets('Jour, capture rapide analysée, Fait, puis Flux', (tester) async {
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
      ai: AiAssistant(ClaudeClient(() async => null), settings),
      notion: NotionService(() async => null),
      encryptionActive: false,
    );

    await tester.runAsync(() async {
      await db.createItem(
        kind: ItemKind.task,
        content: 'Appeler le médecin',
        remindAt: DateTime.now().add(const Duration(hours: 1)),
        context: 'Santé',
      );
      await db.createItem(kind: ItemKind.idea, content: 'Idée de prompt');
    });

    await tester.pumpWidget(
      CoffreApp(
        services: services,
        router: LaunchRouter(
          GlobalKey<NavigatorState>(),
          system,
          notifications,
        ),
      ),
    );
    await settle(tester);

    // Vue Jour : rubrique Maintenant + idée à ne pas perdre.
    expect(find.text('1 chose maintenant.'), findsOneWidget);
    expect(find.text('Appeler le médecin'), findsOneWidget);
    expect(find.text('Tâche · Santé'), findsOneWidget);
    await tester.drag(
      find.byType(CustomScrollView).first,
      const Offset(0, -400),
    );
    await settle(tester);
    expect(find.text('À ne pas perdre'), findsOneWidget);
    expect(find.text('Idée de prompt'), findsOneWidget);
    await tester.drag(
      find.byType(CustomScrollView).first,
      const Offset(0, 800),
    );
    await settle(tester);

    // Capture rapide : aperçu de l'analyse avant envoi, puis enregistrement.
    await tester.enterText(
      find.byType(TextField).last,
      'Il faut que je paye la facture dans 3 jours',
    );
    await settle(tester);
    expect(find.textContaining('Tâche · Admin'), findsOneWidget);
    await tester.tap(find.byTooltip('Enregistrer'));
    await settle(tester);
    expect(find.textContaining('Enregistré · Tâche · Admin'), findsOneWidget);
    final created = (await tester.runAsync(db.allItems))!.last;
    expect(created.content, 'Paye la facture');
    expect(created.raw, 'Il faut que je paye la facture dans 3 jours');
    expect(created.context, 'Admin');
    expect(created.remindAt, isNotNull);

    // Laisse le bandeau de confirmation disparaître avant de toucher la carte.
    await tester.pump(
      const Duration(seconds: 1),
    ); // fin de l'animation d'entrée
    await tester.pump(const Duration(seconds: 6)); // délai de 5 s écoulé
    await tester.pump(const Duration(seconds: 1)); // animation de sortie
    await settle(tester);
    expect(find.textContaining('Enregistré · Tâche'), findsNothing);

    // « Fait » depuis la carte : la tâche quitte la vue Jour, l'alarme est annulée.
    final card = find.ancestor(
      of: find.text('Appeler le médecin'),
      matching: find.byType(ItemCard),
    );
    await tester.tap(find.descendant(of: card, matching: find.text('Fait')));
    await settle(tester);
    expect(find.text('Appeler le médecin'), findsNothing);
    expect(calls, contains('cancel'));

    // Vue Flux, filtre « Fait ».
    FocusManager.instance.primaryFocus?.unfocus();
    await settle(tester);
    await tester.tap(find.text('Flux'));
    await settle(tester);
    final doneChip = find.widgetWithText(ChoiceChip, 'Fait');
    await tester.ensureVisible(doneChip);
    await tester.tap(doneChip);
    await settle(tester);
    expect(find.text('Appeler le médecin'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await settle(tester);
    await tester.runAsync(db.close);
  });
}
