import 'package:coffre/services/ai/claude_client.dart';
import 'package:coffre/services/mail_triage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 11, 12, 8);

  group('parseMailActions', () {
    test('lit le tableau JSON, même entouré de texte', () {
      final actions = parseMailActions(
        'Voici : [{"mail": 2, "type": "facture", "titre": "Payer facture Zalando 49,90 €", '
        '"date": "2026-11-20", "heure": null}, {"mail": 1, "type": "rdv", '
        '"titre": "Dentiste à Waterloo", "date": "2026-11-18", "heure": "14:30"}]',
        2,
      );
      expect(actions, hasLength(2));
      expect(actions[0].type, 'facture');
      expect(actions[0].date, DateTime(2026, 11, 20));
      expect(actions[1].date, DateTime(2026, 11, 18, 14, 30));
      expect(actions[1].hasTime, isTrue);
    });

    test('ignore les entrées invalides et les réponses illisibles', () {
      expect(parseMailActions('rien à signaler', 3), isEmpty);
      expect(parseMailActions('[]', 3), isEmpty);
      final actions = parseMailActions(
        '[{"mail": 9, "type": "facture", "titre": "Hors liste"},'
        ' {"mail": 1, "type": "pub", "titre": "Promo"},'
        ' {"mail": 1, "type": "action", "titre": "Renvoyer le formulaire"}]',
        2,
      );
      expect(actions.single.title, 'Renvoyer le formulaire');
      expect(actions.single.date, isNull);
    });
  });

  group('reminderFor', () {
    test('facture : la veille à 9 h', () {
      const a = MailAction(mail: 1, type: 'facture', title: 'Payer');
      final at = reminderFor(
        MailAction(
          mail: a.mail,
          type: a.type,
          title: a.title,
          date: DateTime(2026, 11, 20),
        ),
        now,
      );
      expect(at, DateTime(2026, 11, 19, 9));
    });

    test('rendez-vous avec heure : à l\'heure dite', () {
      final at = reminderFor(
        MailAction(
          mail: 1,
          type: 'rdv',
          title: 'Dentiste',
          date: DateTime(2026, 11, 18, 14, 30),
          hasTime: true,
        ),
        now,
      );
      expect(at, DateTime(2026, 11, 18, 14, 30));
    });

    test('échéance passée : pas de rappel ; aujourd\'hui : dans 30 min', () {
      expect(
        reminderFor(
          MailAction(
            mail: 1,
            type: 'action',
            title: 'x',
            date: DateTime(2026, 11, 1),
          ),
          now,
        ),
        isNull,
      );
      final today = DateTime(2026, 11, 12, 10);
      expect(
        reminderFor(
          MailAction(
            mail: 1,
            type: 'facture',
            title: 'x',
            date: DateTime(2026, 11, 12),
          ),
          today,
        ),
        today.add(const Duration(minutes: 30)),
      );
    });
  });

  test('describeMails numérote expéditeur, objet et texte', () {
    final text = describeMails(const [
      MailDigest(
        uid: 5,
        from: 'Engie <noreply@engie.be>',
        subject: 'Votre facture',
        text: 'Montant 84,20 €',
      ),
    ]);
    expect(text, contains('--- Mail 1'));
    expect(text, contains('Objet : Votre facture'));
    expect(text, contains('84,20 €'));
  });

  test('cleanText retire le HTML', () {
    expect(
      GmailReader.cleanText(
        '<p>Bonjour&nbsp;<b>J</b></p><style>x{}</style>',
        html: true,
      ),
      'Bonjour J',
    );
  });

  test('tri des mails : Haiku, sans repli serveur', () {
    final body = ClaudeClient.buildBody(
      system: 's',
      prompt: 'p',
      effort: 'low',
      light: true,
    );
    expect(body['model'], 'claude-haiku-5-5');
    expect(body.containsKey('fallbacks'), isFalse);
    final normal = ClaudeClient.buildBody(
      system: 's',
      prompt: 'p',
      effort: 'low',
    );
    expect(normal['fallbacks'], 'default');
  });
}
