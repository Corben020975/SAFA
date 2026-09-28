import 'package:coffre/core/reminder_defaults.dart';
import 'package:coffre/data/app_settings.dart';
import 'package:coffre/data/database.dart';
import 'package:coffre/data/enums.dart';
import 'package:coffre/services/app_lock.dart';
import 'package:coffre/services/capture_analyzer.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';

void main() {
  group('Répétition', () {
    final now = DateTime(2026, 9, 28, 12); // lundi midi

    test('prochaine date : jour, semaine, mois court, jours ouvrables', () {
      final monday9 = DateTime(2026, 9, 28, 9);
      expect(Recurrence.daily.next(monday9, now), DateTime(2026, 9, 29, 9));
      expect(Recurrence.weekly.next(monday9, now), DateTime(2026, 10, 5, 9));
      expect(Recurrence.biweekly.next(monday9, now), DateTime(2026, 10, 12, 9));
      expect(
        Recurrence.monthly.next(
          DateTime(2027, 1, 31, 9),
          DateTime(2027, 1, 31, 10),
        ),
        DateTime(2027, 2, 28, 9),
      );
      expect(
        Recurrence.quarterly.next(monday9, now),
        DateTime(2026, 12, 28, 9),
      );
      expect(Recurrence.yearly.next(monday9, now), DateTime(2027, 9, 28, 9));
      // Vendredi → lundi suivant.
      expect(
        Recurrence.weekdays.next(
          DateTime(2026, 10, 2, 9),
          DateTime(2026, 10, 2, 10),
        ),
        DateTime(2026, 10, 5, 9),
      );
      // Très en retard : on saute directement après maintenant.
      expect(
        Recurrence.weekly.next(DateTime(2026, 8, 3, 9), now),
        DateTime(2026, 10, 5, 9),
      );
    });

    test('« Fait » renvoie un élément répété à sa prochaine date', () async {
      final db = AppDatabase(NativeDatabase.memory());
      final item = await db.createItem(
        kind: ItemKind.task,
        content: 'Réunion d\'équipe',
        remindAt: DateTime.now().subtract(const Duration(hours: 1)),
        recurrence: Recurrence.weekly,
      );
      final next = (await db.setStatus(item.id, ItemStatus.done))!;
      expect(next.status, ItemStatus.todo);
      expect(next.doneAt, isNull);
      expect(next.remindAt!.isAfter(DateTime.now()), isTrue);
      // Même heure (à la minute), une semaine plus tard.
      expect(
        next.remindAt!.difference(item.remindAt!).inMinutes,
        closeTo(7 * 24 * 60, 1),
      );

      final once = await db.createItem(
        kind: ItemKind.task,
        content: 'Unique',
        remindAt: DateTime.now(),
      );
      expect(
        (await db.setStatus(once.id, ItemStatus.done))!.status,
        ItemStatus.done,
      );
      await db.close();
    });

    test(
      'dictée : « chaque lundi à 9h », « tous les soirs », « tous les 3 mois »',
      () {
        final a = CaptureAnalyzer.analyze(
          'Réunion d\'équipe chaque lundi à 9h',
          now: now,
        );
        expect(a.recurrence, Recurrence.weekly);
        expect(a.remindAt, DateTime(2026, 10, 5, 9));
        expect(a.title, 'Réunion d\'équipe');

        final b = CaptureAnalyzer.analyze(
          'Prendre mes médicaments tous les soirs',
          now: now,
        );
        expect(b.recurrence, Recurrence.daily);
        final (eh, em) = ReminderDefaults.evening;
        expect(b.remindAt, DateTime(2026, 9, 28, eh, em));
        expect(b.title, 'Prendre mes médicaments');

        final c = CaptureAnalyzer.analyze(
          'Rapport d\'activité tous les 3 mois',
          now: now,
        );
        expect(c.recurrence, Recurrence.quarterly);
        expect(c.remindAt, isNotNull);

        final d = CaptureAnalyzer.analyze(
          'Point équipe tous les jours à 8h30',
          now: now,
        );
        expect(
          (d.recurrence, d.remindAt),
          (Recurrence.daily, DateTime(2026, 9, 29, 8, 30)),
        );

        expect(
          CaptureAnalyzer.analyze(
            'Appeler le médecin demain',
            now: now,
          ).recurrence,
          Recurrence.none,
        );
      },
    );
  });

  group('Verrouillage', () {
    test('démarrage verrouillé, empreinte, retour après la pause', () async {
      final db = AppDatabase(NativeDatabase.memory());
      final settings = AppSettings(db);
      await settings.setAppLock(true);
      var answer = false;
      final lock = AppLock(
        settings,
        authenticate: (_) async => answer,
        grace: Duration.zero,
      );
      expect(lock.locked, isTrue);
      await lock.unlock();
      expect(lock.locked, isTrue);
      answer = true;
      await lock.unlock();
      expect(lock.locked, isFalse);
      lock.onPaused();
      lock.onResumed();
      expect(lock.locked, isTrue);
      await db.close();
    });

    test('téléphone sans code : verrou désactivé plutôt que bloqué', () async {
      final db = AppDatabase(NativeDatabase.memory());
      final settings = AppSettings(db);
      await settings.setAppLock(true);
      final lock = AppLock(
        settings,
        authenticate: (_) async => throw const LocalAuthException(
          code: LocalAuthExceptionCode.noCredentialsSet,
        ),
      );
      await lock.unlock();
      expect(lock.locked, isFalse);
      expect(settings.appLock, isFalse);
      expect(lock.error, contains('Aucune empreinte'));
      await db.close();
    });
  });
}
