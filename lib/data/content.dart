import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'db.dart';

List<String> _strings(Object? v) => [for (final e in (v as List? ?? const [])) '$e'];

/// One entry of the baseline question bank (`docs/content-schema.md`).
class Question {
  Question(Json j)
      : id = j['id'] as String,
        category = j['category'] as String? ?? 'behavioral',
        competency = j['competency'] as String? ?? 'communication',
        prompt = j['prompt'] as String,
        variants = _strings(j['variants']),
        intent = j['intent'] as String? ?? '',
        framework = j['framework'] as String? ?? 'STAR',
        answerGuide = _strings(j['answerGuide']),
        pitfalls = _strings(j['pitfalls']),
        followUps = _strings(j['followUps']),
        roles = _strings(j['roles']),
        frequency = (j['frequency'] as num?)?.toInt() ?? 2,
        difficulty = (j['difficulty'] as num?)?.toInt() ?? 2;

  final String id, category, competency, prompt, intent, framework;
  final List<String> variants, answerGuide, pitfalls, followUps, roles;
  final int frequency, difficulty;
}

class Exercise {
  Exercise(Json j)
      : id = j['id'] as String,
        type = j['type'] as String,
        placement = j['placement'] == true,
        prompt = j['prompt'] as String,
        choices = _strings(j['choices']),
        answerIndex = j['answer'] is num ? (j['answer'] as num).toInt() : null,
        answerText = j['answer'] is String ? j['answer'] as String : null,
        accept = _strings(j['accept']),
        explanation = j['explanation'] as String? ?? '',
        rubric = _strings(j['rubric']),
        sqlite = j['sqlite'] as String?,
        ordered = j['ordered'] == true;

  final String id, type, prompt, explanation;
  final bool placement;
  final List<String> choices, accept, rubric;
  final int? answerIndex;
  final String? answerText;

  /// A solution the SQL sandbox can run on the practice data, to check a query against.
  final String? sqlite;
  final bool ordered;

  static String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[\s;]+'), ' ').trim();

  /// Whether a typed answer to a `short` exercise matches an accepted one.
  bool matches(String typed) {
    final t = _norm(typed);
    return t.isNotEmpty && [...accept, ?answerText].any((a) => _norm(a) == t);
  }
}

class Lesson {
  Lesson(Json j)
      : id = j['id'] as String,
        title = j['title'] as String,
        minutes = (j['minutes'] as num?)?.toInt() ?? 8,
        body = j['body'] as String? ?? '',
        keyPoints = _strings(j['keyPoints']),
        interviewAngle = j['interviewAngle'] as String? ?? '',
        exercises = [for (final e in (j['exercises'] as List? ?? const [])) Exercise(e as Json)];

  final String id, title, body, interviewAngle;
  final int minutes;
  final List<String> keyPoints;
  final List<Exercise> exercises;
}

class Unit {
  Unit(Json j)
      : id = j['id'] as String,
        title = j['title'] as String,
        summary = j['summary'] as String? ?? '',
        lessons = [for (final l in (j['lessons'] as List? ?? const [])) Lesson(l as Json)];

  final String id, title, summary;
  final List<Lesson> lessons;
}

class SkillModule {
  SkillModule(Json j, this.units)
      : id = j['id'] as String,
        title = j['title'] as String,
        tagline = j['tagline'] as String? ?? '',
        claim = j['claim'] as String? ?? '',
        interviewQuestions = [for (final q in (j['interviewQuestions'] as List? ?? const [])) q as Json],
        resources = [for (final q in (j['resources'] as List? ?? const [])) q as Json],
        labs = [for (final q in (j['labs'] as List? ?? const [])) q as Json],
        pathway = j['pathway'] as Json?,
        unverified = _strings(j['unverified']);

  final String id, title, tagline, claim;
  final List<Unit> units;
  final List<Json> interviewQuestions;

  /// Outside courses and references, and hands-on work in the real tool.
  final List<Json> resources, labs;

  /// When to use outside courses and when these lessons are the better choice.
  final Json? pathway;

  /// What the author could not confirm (`assets/content/authoring.md`), shown
  /// to the learner so a module never looks more certain than it is.
  final List<String> unverified;

  Iterable<Lesson> get lessons => units.expand((u) => u.lessons);
}

class Content {
  Content({required this.questions, required this.modules, required this.stories, required this.facts, required this.dossier});

  final List<Question> questions;
  final List<SkillModule> modules;

  /// The seed story bank; the learner's edits are `story` documents over it.
  final List<Json> stories;
  final String facts, dossier;

  late final Map<String, Question> questionById = {for (final q in questions) q.id: q};

  static const moduleIds = ['sql', 'excel', 'power-bi', 'jira', 'azure-devops', 'ado-test-plans', 'playwright', 'ticket-process', 'documentation'];
  static const categories = ['background', 'motivation', 'self', 'behavioral', 'situational', 'role', 'curveball', 'closing'];

  /// A bundled file that is missing or unreadable is skipped, so one bad
  /// module never stops the app from opening.
  static Future<Object?> _json(String path) async {
    try {
      return jsonDecode(await rootBundle.loadString(path));
    } catch (_) {
      return null;
    }
  }

  /// A file from the learner's own folder, decoded; null when absent or unreadable.
  static Object? _userJson(Directory? user, String path) {
    try {
      final f = File('${user?.path}/$path');
      return user != null && f.existsSync() ? jsonDecode(f.readAsStringSync()) : null;
    } catch (_) {
      return null;
    }
  }

  static String? _userText(Directory? user, String path) {
    try {
      final f = File('${user?.path}/$path');
      return user != null && f.existsSync() && f.lengthSync() > 0 ? f.readAsStringSync() : null;
    } catch (_) {
      return null;
    }
  }

  /// Reads the bundled content, then what the learner's folder ([user],
  /// Documents\HireFly) adds or replaces:
  /// - `career/facts.md`, `career/dossier.md`, `career/stories.json`: their record;
  /// - `career/skills.json` (`{"modules": ["sql", ...]}`): which skills to show, in order;
  /// - `content/skills/<id>/module.json` and its units: new or replacement modules;
  /// - `content/questions/*.json`: more bank questions.
  static Future<Content> load({Directory? user}) async {
    final questions = <Question>[];
    for (final c in categories) {
      final list = await _json('assets/content/questions/$c.json');
      if (list is! List) continue;
      for (final q in list) {
        try {
          questions.add(Question(q as Json));
        } catch (_) {
          // A malformed entry is dropped.
        }
      }
    }
    final modules = <SkillModule>[];
    for (final id in moduleIds) {
      final m = await _json('assets/content/skills/$id/module.json');
      if (m is! Json) continue;
      final units = <Unit>[];
      for (final f in _strings(m['units'])) {
        final u = await _json('assets/content/skills/$id/$f');
        try {
          if (u is Json) units.add(Unit(u));
        } catch (_) {
          // A malformed unit is dropped.
        }
      }
      if (units.isNotEmpty) modules.add(SkillModule(m, units));
    }
    // The learner's own questions and modules.
    final qDir = Directory('${user?.path}/content/questions');
    if (user != null && qDir.existsSync()) {
      final have = {for (final q in questions) q.id};
      for (final f in qDir.listSync().whereType<File>().where((f) => f.path.endsWith('.json'))) {
        try {
          for (final q in jsonDecode(f.readAsStringSync()) as List) {
            final parsed = Question(q as Json);
            if (have.add(parsed.id)) questions.add(parsed);
          }
        } catch (_) {
          // A malformed file is skipped.
        }
      }
    }
    final sDir = Directory('${user?.path}/content/skills');
    if (user != null && sDir.existsSync()) {
      for (final d in sDir.listSync().whereType<Directory>()) {
        final id = d.uri.pathSegments.where((s) => s.isNotEmpty).last;
        final m = _userJson(user, 'content/skills/$id/module.json');
        if (m is! Json) continue;
        final units = <Unit>[];
        for (final f in _strings(m['units'])) {
          final u = _userJson(user, 'content/skills/$id/$f');
          try {
            if (u is Json) units.add(Unit(u));
          } catch (_) {
            // A malformed unit is dropped.
          }
        }
        if (units.isEmpty) continue;
        modules.removeWhere((x) => x.id == m['id']);
        try {
          modules.add(SkillModule(m, units));
        } catch (_) {
          // A malformed module is skipped.
        }
      }
    }
    // Which skills this learner wants, in their order.
    final wanted = _userJson(user, 'career/skills.json');
    if (wanted is Json && wanted['modules'] is List) {
      final order = _strings(wanted['modules']);
      final picked = [for (final id in order) ...modules.where((m) => m.id == id)];
      if (picked.isNotEmpty) {
        modules
          ..clear()
          ..addAll(picked);
      }
    }
    final userStories = _userJson(user, 'career/stories.json');
    final stories = userStories is List ? userStories : await _json('assets/career/stories.json');
    return Content(
      questions: questions,
      modules: modules,
      stories: [for (final s in (stories as List? ?? const [])) if (s is Json) s],
      facts: _userText(user, 'career/facts.md') ?? await rootBundle.loadString('assets/career/facts.md'),
      dossier: _userText(user, 'career/dossier.md') ?? await rootBundle.loadString('assets/career/dossier.md'),
    );
  }
}

/// Overridden in `main` once the bundle is read.
final contentProvider = Provider<Content>((ref) => throw UnimplementedError());

/// The seed stories with the learner's saved edits over them, and any stories
/// they added.
List<Json> mergeStories(List<Json> seed, Map<String, Json> edits) => [
      for (final s in seed) {...s, ...?edits[s['id']]},
      for (final e in edits.entries)
        if (!seed.any((s) => s['id'] == e.key)) {...e.value, 'id': e.key},
    ];

/// The story bank read straight from the database: for work that must not
/// depend on which screen happens to be open.
Future<List<Json>> loadStories(Store store, Content content) async =>
    mergeStories(content.stories, {for (final d in await store.list('story')) d.id: d.data});

/// The story bank with the learner's edits applied.
final storiesProvider = Provider.autoDispose<List<Json>>((ref) {
  final edits = {for (final d in ref.watch(docsProvider(('story', null))).value ?? const <Doc>[]) d.id: d.data};
  return mergeStories(ref.watch(contentProvider).stories, edits);
});
