import 'package:coffre/data/database.dart';
import 'package:coffre/data/enums.dart';
import 'package:coffre/services/day_board.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 9, 28, 10);
  var nextId = 1;

  Item item(
    String content, {
    ItemKind kind = ItemKind.task,
    DateTime? at,
    ItemPriority priority = ItemPriority.normal,
    bool preAlert = false,
    ItemStatus status = ItemStatus.todo,
    DateTime? created,
  }) => Item(
    id: nextId++,
    kind: kind,
    status: status,
    priority: priority,
    content: content,
    tags: const [],
    remindAt: at,
    inbox: true,
    preAlert: preAlert,
    recurrence: Recurrence.none,
    searchText: '',
    createdAt: created ?? now.subtract(const Duration(days: 1)),
    updatedAt: now,
  );

  test('répartition par urgence', () {
    final board = DayBoard.compute([
      item('En retard', at: now.subtract(const Duration(hours: 1))),
      item('Dans 2 h', at: now.add(const Duration(hours: 2))),
      item('Ce soir', at: DateTime(2026, 9, 28, 20)),
      item('Pré-alerte', at: DateTime(2026, 9, 28, 15), preAlert: false),
      item('Jeudi', at: DateTime(2026, 10, 1, 9)),
      item('Le mois prochain', at: DateTime(2026, 10, 30, 9)),
      item('Sans date'),
      item('Urgent sans date', priority: ItemPriority.urgent),
      item('Idée récente', kind: ItemKind.idea),
      item('Déjà fait', status: ItemStatus.done, at: now),
    ], now);

    expect(board.soonItems.map((i) => i.content), [
      'Urgent sans date',
      'En retard',
      'Dans 2 h',
    ]);
    expect(board.todayItems.map((i) => i.content), ['Pré-alerte', 'Ce soir']);
    expect(board.nextItems.single.content, 'Jeudi');
    expect(board.undatedItems.single.content, 'Sans date');
    expect(board.spark?.content, 'Idée récente');
    expect(board.laterCount, 1);
    expect(board.openCount, 9);
    expect(board.headline, '3 choses maintenant.');
    expect(
      board.laterLine,
      'Ensuite : une cette semaine, une tâche sans date, une plus loin.',
    );
  });

  test('pré-alerte : remonte 1 h 30 avant', () {
    final board = DayBoard.compute([
      item('Rdv', at: now.add(const Duration(hours: 4)), preAlert: true),
    ], now.add(const Duration(hours: 2, minutes: 31)));
    expect(board.soonItems.single.content, 'Rdv');
  });

  test('vide', () {
    final board = DayBoard.compute([], now);
    expect(board.isEmpty, isTrue);
    expect(board.headline, 'Rien en cours.');
    expect(board.spark, isNull);
  });

  test('plus tard', () {
    final choices = laterChoices(DateTime(2026, 9, 28, 20));
    expect(choices[1].$1, 'Demain soir');
    expect(choices[1].$2, DateTime(2026, 9, 29, 18));
    expect(choices[2].$2, DateTime(2026, 9, 29, 9));
  });
}
