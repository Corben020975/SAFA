import 'dart:convert';

import 'package:coffre/data/app_settings.dart';
import 'package:coffre/data/database.dart';
import 'package:coffre/data/enums.dart';
import 'package:coffre/services/ai/ai_assistant.dart';
import 'package:coffre/services/ai/ai_engine.dart';
import 'package:coffre/services/ai/claude_client.dart';
import 'package:coffre/services/ai/gemini_client.dart';
import 'package:coffre/services/notion_service.dart';
import 'package:drift/native.dart';
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
    return 'ok';
  }
}

void main() {
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

  group('Gemini', () {
    test('requête, en-têtes, masquage et réponse', () async {
      late http.Request sent;
      final client = GeminiClient(
        () async => 'AIza-test',
        client: MockClient((request) async {
          sent = request;
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'candidates': [
                  {
                    'finishReason': 'STOP',
                    'content': {
                      'parts': [
                        {'text': 'réflexion', 'thought': true},
                        {'text': '- Appeler [PERSONNE 1] '},
                        {'text': 'demain'},
                      ],
                    },
                  },
                ],
              }),
            ),
            200,
          );
        }),
      );
      final db = AppDatabase(NativeDatabase.memory());
      final settings = AppSettings(db);
      await settings.load();
      final claude = _FakeEngine();
      final assistant = AiAssistant(claude, client, settings);

      expect(settings.aiProvider, AiProvider.gemini);
      final answer = await assistant.run(AiAction.steps, _item());

      expect(claude.calls, 0);
      expect(
        sent.url.toString(),
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-flash-latest:generateContent',
      );
      expect(sent.headers['x-goog-api-key'], 'AIza-test');
      final body = jsonDecode(sent.body) as Map<String, dynamic>;
      expect(
        ((body['systemInstruction'] as Map)['parts'] as List).single['text'],
        contains('[PERSONNE 1]'),
      );
      expect(sent.body, isNot(contains('Dupont')));
      expect(answer, '- Appeler Mme Dupont demain');
      await db.close();
    });

    test('modèle retiré : repli sur le suivant', () async {
      final urls = <String>[];
      final client = GeminiClient(
        () async => 'k',
        client: MockClient((request) async {
          urls.add(request.url.pathSegments.last);
          if (urls.length == 1) {
            return http.Response(
              '{"error":{"code":404,"message":"not found"}}',
              404,
            );
          }
          return http.Response(
            '{"candidates":[{"finishReason":"MAX_TOKENS","content":{"parts":[{"text":"OK"}]}}]}',
            200,
          );
        }),
      );
      expect(await client.complete(system: 's', prompt: 'p'), 'OK…');
      expect(urls, [
        'gemini-flash-latest:generateContent',
        'gemini-2.5-flash:generateContent',
      ]);
    });

    test('erreurs traduites', () {
      expect(
        () => GeminiClient.parse(
          400,
          '{"error":{"code":400,"message":"API key not valid.","status":"INVALID_ARGUMENT",'
          '"details":[{"reason":"API_KEY_INVALID"}]}}',
        ),
        throwsA(predicate((e) => '$e'.contains('Clé API refusée'))),
      );
      expect(
        () => GeminiClient.parse(429, '{"error":{"code":429}}'),
        throwsA(predicate((e) => '$e'.contains('Quota gratuit'))),
      );
      expect(
        () => GeminiClient.parse(
          200,
          '{"promptFeedback":{"blockReason":"SAFETY"}}',
        ),
        throwsA(predicate((e) => '$e'.contains('bloqué'))),
      );
      expect(
        () => GeminiClient.parse(
          200,
          '{"candidates":[{"finishReason":"SAFETY","content":{"parts":[]}}]}',
        ),
        throwsA(predicate((e) => '$e'.contains('bloqué'))),
      );
    });

    test('sans clé : message clair', () {
      expect(
        () => GeminiClient(() async => null).complete(system: 's', prompt: 'p'),
        throwsA(predicate((e) => '$e'.contains('clé API Gemini'))),
      );
    });
  });
}
