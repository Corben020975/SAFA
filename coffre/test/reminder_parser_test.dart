import 'package:coffre/core/text_normalize.dart';
import 'package:coffre/services/reminder_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Lundi 28 septembre 2026, 10:00.
  final now = DateTime(2026, 9, 28, 10, 0);

  DateTime? when(String text) => ReminderParser.parse(text, now: now)?.when;

  String stripped(String text) =>
      ReminderParser.strip(text, ReminderParser.parse(text, now: now)!);

  group('détection', () {
    test('demain 9h', () {
      expect(when('Appeler le médecin demain 9h'), DateTime(2026, 9, 29, 9));
      expect(
        when('Appeler le médecin demain à 9h30'),
        DateTime(2026, 9, 29, 9, 30),
      );
      expect(when('demain à 9 heures'), DateTime(2026, 9, 29, 9));
      expect(when('demain 14:15'), DateTime(2026, 9, 29, 14, 15));
    });

    test('parties de journée', () {
      expect(when('demain matin'), DateTime(2026, 9, 29, 9));
      expect(when('ce soir'), DateTime(2026, 9, 28, 18));
      expect(when('cet après-midi'), DateTime(2026, 9, 28, 14));
      expect(when('après-demain soir'), DateTime(2026, 9, 30, 18));
      expect(when('demain midi'), DateTime(2026, 9, 29, 12));
    });

    test('jours de la semaine', () {
      expect(when('réunion lundi à 14h'), DateTime(2026, 10, 5, 14));
      expect(when('vendredi'), DateTime(2026, 10, 2, 9));
      expect(when('mercredi prochain 8h'), DateTime(2026, 9, 30, 8));
    });

    test('dates', () {
      expect(when('rdv le 12/10 à 10h'), DateTime(2026, 10, 12, 10));
      expect(when('rdv le 3 octobre'), DateTime(2026, 10, 3, 9));
      expect(when('le 2 à 11h'), DateTime(2026, 10, 2, 11));
      expect(when('le 15 janvier'), DateTime(2027, 1, 15, 9));
    });

    test('relatif', () {
      expect(
        when('acheter du pain dans 20 minutes'),
        DateTime(2026, 9, 28, 10, 20),
      );
      expect(when('dans une heure'), DateTime(2026, 9, 28, 11));
      expect(when('dans 2h'), DateTime(2026, 9, 28, 12));
      expect(when('dans une demi-heure'), DateTime(2026, 9, 28, 10, 30));
      expect(when('dans 3 jours'), DateTime(2026, 10, 1, 9));
    });

    test('heure seule', () {
      expect(when('à 15h appeler Paul'), DateTime(2026, 9, 28, 15));
      expect(when('à 8h appeler Paul'), DateTime(2026, 9, 29, 8));
      expect(when('rappel à midi'), DateTime(2026, 9, 28, 12));
    });

    test('pas de faux positifs', () {
      expect(when('réunion de 2h avec l équipe'), isNull);
      expect(when('idée pour le site de prompts'), isNull);
      expect(when('demandeur'), isNull);
      expect(when('à 25h'), isNull);
    });
  });

  group('nettoyage du texte', () {
    test('retire la date et le connecteur', () {
      expect(
        stripped('Appeler le médecin pour demain 9h'),
        'Appeler le médecin',
      );
      expect(stripped('Demain à 9h appeler Paul'), 'Appeler Paul');
      expect(
        stripped('Réunion SAFA lundi à 14h, salle 2'),
        'Réunion SAFA, salle 2',
      );
    });
  });

  group('normalisation', () {
    test('accents et casse', () {
      expect(normalizeForSearch('Élève Œuvre ÇA'), 'eleve oeuvre ca');
      expect(foldKeepingLength('Après-midi').length, 'Après-midi'.length);
      expect(normalizeTag('  #Santé Mentale '), 'santé-mentale');
      expect(normalizeTag('###'), isNull);
    });
  });

  test('échéances des mails', () {
    final now = DateTime(2026, 10, 7, 11); // mercredi
    DateTime? at(String text) => ReminderParser.parse(text, now: now)?.when;
    expect(
      at('Envoyer le rapport d’ici la fin de la semaine'),
      DateTime(2026, 10, 9, 9),
    );
    expect(at('Budget pour la fin du mois'), DateTime(2026, 10, 31, 9));
    expect(
      at('Planning à revoir la semaine prochaine'),
      DateTime(2026, 10, 12, 9),
    );
    expect(at('Dossier à rendre pour le 15'), DateTime(2026, 10, 15, 9));
    expect(
      ReminderParser.strip(
        'Envoyer le rapport d’ici la fin de la semaine',
        ReminderParser.parse(
          'Envoyer le rapport d’ici la fin de la semaine',
          now: now,
        )!,
      ),
      'Envoyer le rapport',
    );
  });
}
