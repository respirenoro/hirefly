// The in-app skill builder: the app assigns ids, enforces the content rules and
// only saves a module that passes them.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:project_hirefly/data/content.dart';
import 'package:project_hirefly/data/db.dart';
import 'package:project_hirefly/engine/skill_builder.dart';

Json _exercise(String type, String prompt, {List<String> choices = const [], int correct = 0, List<String> accept = const [], String answer = '', List<String> rubric = const [], bool placement = false}) =>
    {'type': type, 'prompt': prompt, 'choices': choices, 'correctIndex': correct, 'accept': accept, 'answerText': answer, 'explanation': 'Because.', 'rubric': rubric, 'placement': placement};

Json _lesson(String title, {bool open = true}) => {
      'title': title,
      'minutes': 9,
      'body': List.filled(60, 'A worked example about cases and queues.').join(' '),
      'keyPoints': ['One', 'Two', 'Three'],
      'interviewAngle': 'Say what you did and what you have only studied.',
      'exercises': [
        _exercise('mcq', 'Pick one for $title', choices: ['a', 'b', 'c', 'd'], correct: 2),
        _exercise('short', 'Name it for $title', accept: ['A Case'], answer: 'Case', placement: true),
        // Unusable: one choice and an index outside it. The app drops it.
        _exercise('mcq', 'Broken for $title', choices: ['a'], correct: 5),
        // An open exercise cannot be a placement question, whatever the model says.
        if (open) _exercise('open', 'Explain $title', answer: 'A full answer.', rubric: ['Says why'], placement: true),
        _exercise('mcq', 'Another for $title', choices: ['a', 'b', 'c']),
      ],
    };

AskModule fake({bool open = true}) => ({required task, required instructions, required schema}) async => switch (task) {
      'module-outline' => {
          'title': 'Salesforce',
          'tagline': 'Cases, queues and reports.',
          'claim': 'Logged cases daily.',
          'units': [
            for (final u in ['Basics', 'Cases', 'Reports', 'In the interview'])
              {
                'title': u,
                'summary': 'About $u.',
                'lessons': [
                  {'title': '$u one', 'covers': 'x'},
                  {'title': '$u two', 'covers': 'y'},
                ],
              },
          ],
          'interviewQuestions': [for (var i = 1; i <= 8; i++) 'Question $i?'],
          'unverified': ['Edition names'],
        },
      'module-unit' => {
          'lessons': [_lesson('${instructions.hashCode} one', open: open), _lesson('${instructions.hashCode} two', open: open)],
        },
      _ => {
          'answers': [
            for (var i = 1; i <= 8; i++) {'prompt': 'Question $i?', 'strongAnswer': 'I logged cases and can explain it.'},
          ],
        },
    };

void main() {
  late Directory home;
  setUp(() => home = Directory.systemTemp.createTempSync('hirefly_builder_'));
  tearDown(() => home.deleteSync(recursive: true));

  test('a built module is saved with app-assigned ids and loads as content', () async {
    File('${home.path}/career/skills.json')
      ..createSync(recursive: true)
      ..writeAsStringSync(jsonEncode({
        'modules': ['sql'],
      }));
    final steps = <String>[];
    final id = await SkillBuilder(ask: fake(), home: home, takenIds: {'sql', 'salesforce'}, now: () => DateTime(2026, 11, 12))
        .build(const SkillRequest(skill: 'Salesforce', claim: 'Logged cases', level: 'User, never admin'), onProgress: steps.add);

    expect(id, 'salesforce-2', reason: 'an id in use is not overwritten');
    expect(steps.first, 'Planning the module');
    final dir = '${home.path}/content/skills/$id';
    final module = jsonDecode(File('$dir/module.json').readAsStringSync()) as Json;
    expect(module['units'], ['unit-1.json', 'unit-2.json', 'unit-3.json', 'unit-4.json']);
    expect(module['resources'], isEmpty, reason: 'no web access, so no links');
    expect((module['unverified'] as List).first, contains('2026-11-12'));
    expect(module['unverified'], contains('Edition names'));
    expect(((module['interviewQuestions'] as List).first as Json)['id'], 'salesforce-2-iq-1');

    final unit = Unit(jsonDecode(File('$dir/unit-2.json').readAsStringSync()) as Json);
    final lesson = unit.lessons.first;
    expect(lesson.id, 'salesforce-2-u2-l1');
    expect(lesson.exercises.map((e) => e.id), ['salesforce-2-u2-l1-e1', 'salesforce-2-u2-l1-e2', 'salesforce-2-u2-l1-e3', 'salesforce-2-u2-l1-e4']);
    expect(lesson.exercises.where((e) => e.placement).single.type, 'short');
    expect(lesson.exercises[1].matches('a case'), isTrue);

    final loaded = SkillModule(module, [for (final f in module['units'] as List) Unit(jsonDecode(File('$dir/$f').readAsStringSync()) as Json)]);
    expect(loaded.lessons.length, 8);
    expect(loaded.unverified.length, 2);

    expect((jsonDecode(File('${home.path}/career/skills.json').readAsStringSync()) as Json)['modules'], ['sql', id]);
  });

  test('a module that breaks the content rules is not saved', () async {
    final builder = SkillBuilder(ask: fake(open: false), home: home, takenIds: const {});
    await expectLater(
      builder.build(const SkillRequest(skill: 'Postman', claim: '', level: '')),
      throwsA(isA<SkillBuildFailure>().having((e) => e.message, 'message', contains('no open exercise'))),
    );
    expect(Directory('${home.path}/content/skills').existsSync(), isFalse);
  });

  test('the authoring standard is bundled for the assistant', () {
    expect(File('pubspec.yaml').readAsStringSync(), contains('assets/content/authoring.md'));
    expect(File('assets/content/authoring.md').readAsStringSync(), contains('Never write a web address from memory'));
  });
}
