import 'dart:convert';

import 'package:coffre/data/app_settings.dart';
import 'package:coffre/data/database.dart';
import 'package:coffre/data/enums.dart';
import 'package:coffre/services/ai/ai_assistant.dart';
import 'package:coffre/services/ai/ai_engine.dart';
import 'package:coffre/services/ai/claude_client.dart';
import 'package:coffre/services/ai/nano_client.dart';
import 'package:coffre/services/notion_service.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Item _item({
  String content = 'Rappeler Mme Dupont pour le dossier AF',
  DateTime? at,
}) => Item(
  id: 1,
  kind: ItemKind.task,
  status: ItemStatus.todo,
  priority: ItemPriority.high,
  content: content,
  tags: const ['cpas'],
  remindAt: at,
  context: 'Travail',
  inbox: true,
  preAlert: false,
  searchText: '',
  createdAt: DateTime(2026, 9, 28),
  updatedAt: DateTime(2026, 9, 28),
);

class _FakeEngine implements AiEngine {
  _FakeEngine([this.answer = 'ok']);
  final String answer;
  String? system;
  String? prompt;
  String? effort;
  int calls = 0;

  @override
  Future<String> complete({
    required String system,
    required String prompt,
    String effort = 'low',
  }) async {
    calls++;
    this.system = system;
    this.prompt = prompt;
    this.effort = effort;
    return answer;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Claude', () {
    test(
      'requête : modèle, repli serveur, en-têtes, et données masquées',
      () async {
        late http.Request sent;
        final client = ClaudeClient(
          () async => 'sk-test',
          client: MockClient((request) async {
            sent = request;
            return http.Response(
              jsonEncode({
                'stop_reason': 'end_turn',
                'content': [
                  {'type': 'text', 'text': '- Appeler [PERSONNE 1] demain'},
                ],
              }),
              200,
            );
          }),
        );
        final db = AppDatabase(NativeDatabase.memory());
        final settings = AppSettings(db);
        await settings.setAiProvider(AiProvider.claude);
        final assistant = AiAssistant(client, _FakeEngine(), settings);

        final answer = await assistant.run(AiAction.steps, _item());

        final body = jsonDecode(sent.body) as Map<String, dynamic>;
        expect(body['model'], 'claude-opus-5');
        expect(body['fallbacks'], 'default');
        expect(body['output_config'], {'effort': 'medium'});
        expect(sent.headers['x-api-key'], 'sk-test');
        expect(sent.headers['anthropic-version'], '2023-06-01');
        expect(
          sent.headers['anthropic-beta'],
          'server-side-fallback-2026-07-01',
        );
        // Le nom n'est jamais envoyé, mais revient dans la réponse.
        expect(sent.body, isNot(contains('Dupont')));
        expect(answer, '- Appeler Mme Dupont demain');
        expect(AiAssistant.parseSteps(answer), ['Appeler Mme Dupont demain']);
        await db.close();
      },
    );

    test('refus, clé invalide, texte seulement', () {
      expect(
        () => ClaudeClient.parse(
          200,
          jsonEncode({'stop_reason': 'refusal', 'content': []}),
        ),
        throwsA(isA<AiException>()),
      );
      expect(
        () => ClaudeClient.parse(
          401,
          jsonEncode({
            'error': {'message': 'invalid x-api-key'},
          }),
        ),
        throwsA(predicate((e) => '$e'.contains('Clé API refusée'))),
      );
      final text = ClaudeClient.parse(
        200,
        jsonEncode({
          'stop_reason': 'end_turn',
          'content': [
            {'type': 'thinking', 'thinking': ''},
            {'type': 'text', 'text': 'Bonjour'},
          ],
        }),
      );
      expect(text, 'Bonjour');
    });

    test('sans clé : message clair', () async {
      final client = ClaudeClient(() async => null);
      expect(
        () => client.complete(system: 's', prompt: 'p'),
        throwsA(predicate((e) => '$e'.contains('clé API'))),
      );
    });
  });

  group('Notion', () {
    test('bases partagées : titre et propriétés détectés', () async {
      final notion = NotionService(
        () async => 'ntn_test',
        client: MockClient((request) async {
          expect(request.headers['Notion-Version'], '2025-09-03');
          expect(jsonDecode(request.body)['filter'], {
            'property': 'object',
            'value': 'data_source',
          });
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'results': [
                  {
                    'object': 'data_source',
                    'id': 'ds-1',
                    'title': [
                      {'plain_text': 'Tâches SAFA'},
                    ],
                    'properties': {
                      'Nom': {'type': 'title'},
                      'Échéance': {'type': 'date'},
                    },
                  },
                ],
              }),
            ),
            200,
          );
        }),
      );
      final targets = await notion.listTargets();
      expect(targets.single.name, 'Tâches SAFA');
      expect(targets.single.titleProp, 'Nom');
      expect(targets.single.dateProp, 'Échéance');
    });

    test('page créée dans la source de données, avec date', () {
      const target = NotionTarget(
        id: 'ds-1',
        name: 'x',
        titleProp: 'Nom',
        dateProp: 'Échéance',
      );
      final body = NotionService.pageBody(
        target,
        _item(
          content: 'Préparer réunion\nOrdre du jour',
          at: DateTime(2026, 9, 29, 9),
        ),
      );
      expect(body['parent'], {
        'type': 'data_source_id',
        'data_source_id': 'ds-1',
      });
      final props = body['properties'] as Map;
      expect(
        ((props['Nom'] as Map)['title'] as List).single['text']['content'],
        'Préparer réunion',
      );
      expect(
        ((props['Échéance'] as Map)['date'] as Map)['start'],
        startsWith('2026-09-29T09:00:00'),
      );
      expect((body['children'] as List).length, 2);
    });

    test('erreur 404 expliquée', () async {
      final notion = NotionService(
        () async => 'ntn_test',
        client: MockClient(
          (_) async => http.Response(jsonEncode({'message': 'not found'}), 404),
        ),
      );
      expect(
        notion.listTargets(),
        throwsA(predicate((e) => '$e'.contains('partage-la'))),
      );
    });
  });

  group('Gemini Nano', () {
    const channel = MethodChannel('coffre/nano');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    test('par défaut : moteur local, texte envoyé tel quel', () async {
      final db = AppDatabase(NativeDatabase.memory());
      final settings = AppSettings(db);
      await settings.load();
      final claude = _FakeEngine();
      final nano = _FakeEngine('- Appeler Mme Dupont');
      final assistant = AiAssistant(claude, nano, settings);

      expect(settings.aiProvider, AiProvider.nano);
      final answer = await assistant.run(AiAction.develop, _item());

      expect(claude.calls, 0);
      expect(nano.prompt, contains('Mme Dupont'));
      expect(nano.system, isNot(contains('[PERSONNE')));
      expect(nano.system, contains('80 à 150'));
      expect(nano.effort, 'medium');
      expect(answer, '- Appeler Mme Dupont');
      await db.close();
    });

    test('statut, génération et erreurs du pont Android', () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        switch (call.method) {
          case 'status':
            return {'status': 'downloadable'};
          case 'generate':
            final prompt = (call.arguments as Map)['prompt'] as String;
            if (prompt == 'bg') {
              throw PlatformException(
                code: 'generate',
                message: 'Inference in background is not allowed',
              );
            }
            return '  Réponse locale  ';
        }
        return null;
      });
      final nano = NanoClient();

      expect(await nano.status(), NanoStatus.downloadable);
      expect(
        await nano.complete(system: 's', prompt: 'x' * 7000, effort: 'medium'),
        'Réponse locale',
      );
      final args = calls.last.arguments as Map;
      expect(args['maxTokens'], 1024);
      expect((args['prompt'] as String).length, NanoClient.maxInputChars + 1);
      expect(
        () => nano.complete(system: 's', prompt: 'bg'),
        throwsA(predicate((e) => '$e'.contains('Garde Coffre ouvert'))),
      );
    });

    test('hors Android : indisponible, sans planter', () async {
      expect(await NanoClient().status(), NanoStatus.unavailable);
    });
  });
}
