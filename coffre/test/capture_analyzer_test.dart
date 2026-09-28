import 'package:coffre/data/enums.dart';
import 'package:coffre/services/capture_analyzer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Lundi 28 septembre 2026, 10:00.
  final now = DateTime(2026, 9, 28, 10);
  Analysis read(String text) => CaptureAnalyzer.analyze(text, now: now);

  test('tâche datée : titre nettoyé, contexte, priorité haute (< 36 h)', () {
    final a = read('Il faut que je appelle le dentiste demain à 19h');
    expect(a.kind, ItemKind.task);
    expect(a.title, 'Appelle le dentiste');
    expect(a.remindAt, DateTime(2026, 9, 29, 19));
    expect(a.context, 'Santé');
    expect(a.priority, ItemPriority.high);
    expect(a.raw, 'Il faut que je appelle le dentiste demain à 19h');
  });

  test('idée', () {
    final a = read('Idée : carnet sans dossiers');
    expect(a.kind, ItemKind.idea);
    expect(a.title, 'Carnet sans dossiers');
    expect(a.context, isNull);
    expect(a.priority, ItemPriority.normal);
  });

  test('échéance administrative lointaine', () {
    final a = read('Échéance le 3 octobre, dossier impôts');
    expect(a.kind, ItemKind.task);
    expect(a.context, 'Admin');
    expect(a.remindAt, DateTime(2026, 10, 3, 9));
    expect(a.priority, ItemPriority.normal);
    expect(a.title, 'Dossier impôts');
  });

  test('urgent et travail', () {
    final a = read('urgent : rappeler la cheffe du CPAS');
    expect(a.priority, ItemPriority.urgent);
    expect(a.context, 'Travail');
    expect(a.title, 'Rappeler la cheffe du CPAS');
  });

  test('note simple, sans changement', () {
    final a = read('Code du portail : 4512');
    expect(a.kind, ItemKind.note);
    expect(a.raw, isNull);
    expect(a.title, 'Code du portail : 4512');
  });

  test('rappel de pensée', () {
    final a = read('rappelle-moi de payer le loyer vendredi');
    expect(a.kind, ItemKind.task);
    expect(a.title, 'Payer le loyer');
    expect(a.context, 'Admin');
    expect(a.remindAt, DateTime(2026, 10, 2, 9));
  });

  test('hockey et déplacement', () {
    expect(read('Entraînement hockey jeudi 20h').context, 'Hockey');
    expect(read('Train pour Bruxelles à 8h').context, 'Déplacement');
  });
}
