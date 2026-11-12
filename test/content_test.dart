// The bundled content must load into the app's own models: one bad file would
// silently drop a module or part of the question bank. Runnable SQL checks
// are run here, so a broken model query never reaches the learner.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:project_hirefly/data/content.dart';
import 'package:project_hirefly/data/db.dart';
import 'package:project_hirefly/engine/export.dart';
import 'package:project_hirefly/engine/sandbox.dart';

Object? read(String path) => jsonDecode(File(path).readAsStringSync());

SkillModule load(String id) {
  final m = read('assets/content/skills/$id/module.json') as Json;
  return SkillModule(m, [for (final f in m['units'] as List) Unit(read('assets/content/skills/$id/$f') as Json)]);
}

void main() {
  final pubspec = File('pubspec.yaml').readAsStringSync();

  test('question bank loads, ids are unique, values are in the schema lists', () {
    const frameworks = {'STAR', 'PAR', 'Present-Past-Future', 'Claim-Evidence-Tie', 'Weakness-Action-Progress', 'Structure-Then-Answer', 'Direct'};
    const roles = {'any', 'qa', 'ba', 'po', 'pm', 'support', 'implementation', 'ops', 'data', 'cs', 'healthcare'};
    final ids = <String>{}, prompts = <String>{};
    for (final c in Content.categories) {
      final list = read('assets/content/questions/$c.json') as List;
      expect(list, isNotEmpty, reason: c);
      for (final j in list) {
        final q = Question(j as Json);
        expect(ids.add(q.id), isTrue, reason: 'duplicate ${q.id}');
        expect(prompts.add(q.prompt.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim()), isTrue, reason: 'duplicate prompt ${q.id}');
        expect(q.category, c, reason: q.id);
        expect(frameworks, contains(q.framework), reason: q.id);
        expect(q.roles, isNotEmpty, reason: q.id);
        expect(roles.containsAll(q.roles), isTrue, reason: '${q.id} ${q.roles}');
        expect(q.intent, isNotEmpty, reason: q.id);
        expect(q.answerGuide, isNotEmpty, reason: q.id);
      }
    }
    expect(ids.length, greaterThanOrEqualTo(320));
  });

  test('every skill module loads and each exercise can be answered', () {
    final ids = <String>{};
    for (final id in Content.moduleIds) {
      expect(pubspec, contains('assets/content/skills/$id/'), reason: '$id is not bundled');
      final module = load(id);
      expect(module.id, id);
      expect(module.lessons.length, greaterThanOrEqualTo(12), reason: id);
      expect(module.interviewQuestions.length, greaterThanOrEqualTo(6), reason: id);
      for (final l in module.lessons) {
        expect(ids.add(l.id), isTrue, reason: 'duplicate ${l.id}');
        expect(l.body.length, greaterThan(400), reason: l.id);
        expect(l.exercises.where((e) => e.placement).length, 1, reason: '${l.id} placement');
        for (final e in l.exercises) {
          expect(ids.add(e.id), isTrue, reason: 'duplicate ${e.id}');
          switch (e.type) {
            case 'mcq':
              expect(e.choices.length, greaterThanOrEqualTo(2), reason: e.id);
              expect(e.answerIndex, inInclusiveRange(0, e.choices.length - 1), reason: e.id);
            case 'short':
              expect(e.matches(e.answerText ?? e.accept.first), isTrue, reason: e.id);
            case 'open':
              expect(e.answerText, isNotNull, reason: e.id);
              expect(e.placement, isFalse, reason: '${e.id}: an open exercise cannot be a placement question');
            default:
              fail('${e.id}: unknown type ${e.type}');
          }
        }
      }
    }
  });

  test('labs have steps and a visible result; every resource is a web link', () {
    for (final id in Content.moduleIds) {
      final module = load(id);
      final labIds = <String>{};
      for (final lab in module.labs) {
        expect(labIds.add('${lab['id']}'), isTrue, reason: 'duplicate lab ${lab['id']}');
        expect('${lab['title']}', isNotEmpty, reason: '${lab['id']}');
        expect((lab['steps'] as List).length, greaterThanOrEqualTo(3), reason: '${lab['id']}');
        expect(lab['check'] as List, isNotEmpty, reason: '${lab['id']}');
      }
      for (final r in module.resources) {
        final uri = Uri.tryParse('${r['url']}');
        expect(uri != null && uri.scheme == 'https' && uri.host.contains('.'), isTrue, reason: '$id resource ${r['title']}: ${r['url']}');
        expect('${r['title']}', isNotEmpty);
        expect('${r['why']}', isNotEmpty, reason: '$id resource ${r['title']}');
      }
    }
  });

  test('every runnable SQL check runs on the practice data and returns rows', () {
    final box = Sandbox(File('assets/content/datasets/practice.sql').readAsStringSync());
    var n = 0;
    for (final l in load('sql').lessons) {
      for (final e in l.exercises.where((e) => e.sqlite != null)) {
        final r = box.run(e.sqlite!, limit: 100000);
        expect(r.error, isNull, reason: '${e.id}: ${r.error}');
        expect(r.columns, isNotEmpty, reason: e.id);
        expect(r.rows, isNotEmpty, reason: '${e.id} returns no rows');
        // The model query must pass its own check.
        expect(compareResults(box.run(e.sqlite!, limit: 100000), r, ordered: e.ordered), isNull, reason: e.id);
        n++;
      }
    }
    expect(n, greaterThanOrEqualTo(30));
  });

  test('the lesson sample database loads and every exported data file is bundled', () {
    final sample = Sandbox(File('assets/content/datasets/lesson_sample.sql').readAsStringSync());
    expect(sample.run('SELECT COUNT(*) FROM shifts').rows.single.single, 8);
    for (final f in datasetFiles) {
      expect(File('assets/content/datasets/$f').existsSync(), isTrue, reason: f);
    }
    expect(pubspec, contains('assets/content/datasets/'));
  });

  test('the bundled story bank, when it has stories, is well formed', () {
    final stories = read('assets/career/stories.json') as List;
    for (final s in stories.cast<Json>()) {
      expect(s['id'], startsWith('story-'));
      expect(s['competencies'], isNotEmpty);
    }
  });
}
