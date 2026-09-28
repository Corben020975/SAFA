import 'package:coffre/services/ai/pseudonymizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('masque puis restaure les données personnelles', () {
    final p = Pseudonymizer();
    const text =
        'Rappeler Mme Dupont (0471 23 45 67, marie.dupont@mail.be) pour le dossier AF. '
        'NN 85.07.30-033.28, IBAN BE71 0961 2345 6769. Voir aussi M. Van Damme puis Mme Dupont.';
    final masked = p.mask(text);

    expect(masked, isNot(contains('Dupont')));
    expect(masked, isNot(contains('Van Damme')));
    expect(masked, isNot(contains('0471')));
    expect(masked, isNot(contains('marie.dupont')));
    expect(masked, isNot(contains('85.07.30')));
    expect(masked, isNot(contains('BE71')));
    // Même personne → même marqueur.
    expect('[PERSONNE 1]'.allMatches(masked).length, 2);
    expect(masked, contains('[PERSONNE 2]'));

    final answer = 'Appelle [PERSONNE 1] au [TELEPHONE 1], puis [PERSONNE 2].';
    expect(
      p.unmask(answer),
      'Appelle Mme Dupont au 0471 23 45 67, puis M. Van Damme.',
    );
  });

  test('texte sans donnée personnelle inchangé', () {
    final p = Pseudonymizer();
    const text = 'Préparer la réunion d\'équipe SAFA de lundi à 14h.';
    expect(p.mask(text), text);
    expect(p.maskedCount, 0);
  });
}
