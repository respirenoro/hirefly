import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_hirefly/ai/ai_client.dart';
import 'package:project_hirefly/data/content.dart';
import 'package:project_hirefly/data/db.dart';
import 'package:project_hirefly/engine/engine.dart';
import 'package:project_hirefly/engine/intake.dart';
import 'package:project_hirefly/engine/sessions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the learner\'s folder supplies the record, chosen skills, and extra content', () async {
    final user = Directory.systemTemp.createTempSync('hirefly_user_');
    addTearDown(() => user.deleteSync(recursive: true));
    void put(String path, Object body) => File('${user.path}/$path')
      ..createSync(recursive: true)
      ..writeAsStringSync(body is String ? body : jsonEncode(body));
    put('career/facts.md', '# Facts\nWorked at Example Co.');
    put('career/stories.json', [{'id': 'story-x', 'title': 'Mine', 'competencies': ['conflict']}]);
    put('career/skills.json', {'modules': ['jira', 'sql', 'tableau']});
    put('content/questions/extra.json', [{'id': 'x-1', 'category': 'role', 'competency': 'data', 'prompt': 'What is a dimension in Tableau?', 'roles': ['data']}]);
    put('content/skills/tableau/module.json', {'id': 'tableau', 'title': 'Tableau', 'units': ['unit-1.json']});
    put('content/skills/tableau/unit-1.json', {'id': 'tab-u1', 'title': 'Basics', 'lessons': [{'id': 'tab-u1-l1', 'title': 'Marks', 'body': 'x', 'exercises': []}]});
    put('content/skills/broken/module.json', '{not json');

    final base = await Content.load();
    final c = await Content.load(user: user);
    expect(c.facts, contains('Example Co.'));
    expect(c.dossier, base.dossier, reason: 'a file that is absent falls back to the bundled one');
    expect(c.stories.single['id'], 'story-x');
    expect([for (final m in c.modules) m.id], ['jira', 'sql', 'tableau']);
    expect(c.questions.length, base.questions.length + 1);
    expect(c.questionById['x-1']!.prompt, contains('Tableau'));
    expect(base.modules.length, 9);
  });

  group('a brief and coaching supplied from outside', () {
    late Store store;
    late Sessions sessions;
    late String id;

    setUp(() async {
      store = Store(AppDatabase(NativeDatabase.memory()));
      final content = await Content.load();
      sessions = Sessions(store, content, AiClient(store), () async => const []);
      id = await sessions.create({'company': 'Acme', 'role': 'QA Analyst', 'posting': 'Write test cases. Use SQL.', 'intensity': 1});
    });

    test('the request carries them', () async {
      final f = File('${Directory.systemTemp.createTempSync('hirefly_req_').path}/r.json')
        ..writeAsStringSync(jsonEncode({'role': 'QA', 'brief': {'summary': 's'}, 'tailored': [{'prompt': 'p'}]}));
      final r = await readInboxFile(f);
      expect(r.brief!['summary'], 's');
      expect(r.tailored.length, 1);
    });

    test('a partial brief is completed; tailored questions join the plan once', () async {
      final before = (await store.list('item', parent: id)).length;
      final tailored = [
        {'prompt': 'How would you test our claims portal?', 'category': 'role', 'intent': 'Test design', 'guide': ['Start from the user stories']},
        {'prompt': 'how would you test our claims portal?'},
        {'prompt': ''},
        {'prompt': 'Why Acme?', 'category': 'nonsense'},
      ];
      await sessions.applyBrief(id, {'summary': 'A QA role.', 'gaps': [{'gap': 'Automation'}], 'whatTheyWant': 'not a list'}, tailored);
      final brief = (await store.get(id))!.data['brief'] as Json;
      expect(brief['summary'], 'A QA role.');
      expect(brief['whatTheyWant'], isEmpty);
      expect((brief['gaps'] as List).single, {'gap': 'Automation', 'howToAnswer': ''});
      expect(brief['questionsToAsk'], isEmpty);
      final items = await store.list('item', parent: id);
      final added = items.where((d) => d.data['source'] == 'tailored').toList();
      expect(items.length, before + 2);
      expect(added.last.data['category'], 'role');
      expect(added.every((d) => isActive(d.data)), isTrue);
    });

    test('coaching lands on the right answer; a bad result is refused', () async {
      final item = (await store.list('item', parent: id)).first;
      expect(await sessions.applyCoach(item.id, {'score': 14, 'verdict': 'Good', 'fixes': ['Add the number']}), isTrue);
      final coach = (await store.get(item.id))!.data['coach'] as Json;
      expect(coach['score'], 10);
      expect(coach['fixes'], ['Add the number']);
      expect(coach['strengths'], isEmpty);
      expect(await sessions.applyCoach(item.id, {'verdict': 'no score'}), isFalse);
      expect(await sessions.applyCoach('nope', {'score': 5}), isFalse);
      expect(await sessions.applyCoach(id, {'score': 5}), isFalse, reason: 'a role is not an answer');
    });
  });
}
