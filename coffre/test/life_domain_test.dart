import 'package:coffre/core/life_domain.dart';
import 'package:coffre/data/database.dart';
import 'package:coffre/data/enums.dart';
import 'package:flutter_test/flutter_test.dart';

Item _item({
  String content = 'Titre',
  String? context,
  List<String> tags = const [],
}) {
  final now = DateTime(2026, 11, 11);
  return Item(
    id: 1,
    kind: ItemKind.task,
    status: ItemStatus.todo,
    priority: ItemPriority.normal,
    content: content,
    tags: tags,
    inbox: true,
    preAlert: false,
    recurrence: Recurrence.none,
    searchText: '',
    createdAt: now,
    updatedAt: now,
    context: context,
  );
}

void main() {
  group('mapNotionTagsToContext', () {
    test('Réunion / Suivi → Travail', () {
      expect(mapNotionTagsToContext(['suivi']), 'Travail');
      expect(mapNotionTagsToContext(['réunion']), 'Travail');
      expect(mapNotionTagsToContext(['appel']), 'Travail');
    });

    test('Admin et Santé', () {
      expect(mapNotionTagsToContext(['admin']), 'Admin');
      expect(mapNotionTagsToContext(['santé']), 'Santé');
    });
  });

  group('itemIsPro / Perso', () {
    test('contexte Travail est pro', () {
      expect(itemIsPro(_item(context: 'Travail')), isTrue);
      expect(itemIsPerso(_item(context: 'Perso')), isTrue);
    });

    test('tag notion + suivi est pro', () {
      expect(itemIsPro(_item(tags: ['notion', 'suivi'])), isTrue);
    });

    test('Santé est perso', () {
      expect(itemIsPro(_item(context: 'Santé')), isFalse);
    });
  });

  group('splitActionTitle', () {
    test('extrait Répondre à …', () {
      final s = splitActionTitle(
        'Répondre à MNL — Factures en souffrance\nnotes',
      );
      expect(s.verb, 'Répondre');
      expect(s.title, startsWith('MNL'));
    });

    test('ne découpe pas Appeler le médecin', () {
      final s = splitActionTitle('Appeler le médecin');
      expect(s.verb, isNull);
      expect(s.title, 'Appeler le médecin');
    });

    test('sans verbe', () {
      final s = splitActionTitle('Idée carnet de prompts');
      expect(s.verb, isNull);
      expect(s.title, 'Idée carnet de prompts');
    });
  });

  group('filterByDayMode', () {
    test('sépare pro et perso', () {
      final items = [
        _item(context: 'Travail', content: 'A'),
        _item(context: 'Perso', content: 'B'),
      ];
      expect(filterByDayMode(items, DayMode.pro).single.content, 'A');
      expect(filterByDayMode(items, DayMode.perso).single.content, 'B');
      expect(filterByDayMode(items, DayMode.all), hasLength(2));
    });

    test('une capture sans contexte reste visible des deux côtés', () {
      final items = [_item(content: 'Sans contexte')];
      expect(filterByDayMode(items, DayMode.pro), hasLength(1));
      expect(filterByDayMode(items, DayMode.perso), hasLength(1));
    });
  });
}
