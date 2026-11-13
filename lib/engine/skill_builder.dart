// Builds a new skill module with the assistant and saves it to the learner's
// folder, where `Content.load` picks it up at the next start. The rules the
// assistant follows are `assets/content/authoring.md`, the same file a Claude
// Code session is pointed at. The app owns the flow and every id; the model
// writes one piece at a time.
import 'dart:convert';
import 'dart:io';

import '../ai/prompts.dart';
import '../data/db.dart';

/// One structured request to the assistant.
typedef AskModule = Future<Json> Function({required String task, required String instructions, required Map<String, Object?> schema});

class SkillRequest {
  const SkillRequest({required this.skill, required this.claim, required this.level, this.roles = ''});

  /// The skill's name, what the resume says about it, the real level with what
  /// must never be claimed, and the roles being targeted.
  final String skill, claim, level, roles;
}

class SkillBuildFailure implements Exception {
  const SkillBuildFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

String skillSlug(String name) {
  final s = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
  return s.isEmpty ? 'skill' : s;
}

List<String> _texts(Object? v) => [for (final e in (v as List? ?? const [])) '$e'.trim()].where((s) => s.isNotEmpty).toList();

/// Turns what the model wrote for one lesson into the file format, with ids
/// the app assigns. Throws when the lesson cannot meet the content rules.
Json lessonFromDraft(Json d, String id) {
  final exercises = <Json>[];
  var n = 0;
  for (final raw in (d['exercises'] as List? ?? const []).whereType<Json>()) {
    final type = '${raw['type']}', prompt = '${raw['prompt'] ?? ''}'.trim();
    if (prompt.isEmpty) continue;
    final eid = '$id-e${n + 1}';
    final explanation = '${raw['explanation'] ?? ''}'.trim();
    switch (type) {
      case 'mcq':
        final choices = _texts(raw['choices']);
        final answer = (raw['correctIndex'] as num?)?.toInt() ?? -1;
        if (choices.length < 3 || answer < 0 || answer >= choices.length) continue;
        exercises.add({'id': eid, 'type': 'mcq', 'prompt': prompt, 'choices': choices, 'answer': answer, 'explanation': explanation});
      case 'short':
        final answer = '${raw['answerText'] ?? ''}'.trim();
        final accept = {for (final a in [..._texts(raw['accept']), answer]) a.toLowerCase().replaceAll(RegExp(r'\s+'), ' ')}.toList();
        if (answer.isEmpty) continue;
        exercises.add({'id': eid, 'type': 'short', 'prompt': prompt, 'accept': accept, 'answer': answer, 'explanation': explanation});
      case 'open':
        final answer = '${raw['answerText'] ?? ''}'.trim(), rubric = _texts(raw['rubric']);
        if (answer.isEmpty || rubric.isEmpty) continue;
        exercises.add({'id': eid, 'type': 'open', 'prompt': prompt, 'answer': answer, 'rubric': rubric});
      default:
        continue;
    }
    n++;
  }
  // Exactly one placement question, and it must be checkable by the app.
  final wanted = (d['exercises'] as List? ?? const []).whereType<Json>().where((e) => e['placement'] == true).map((e) => '${e['prompt'] ?? ''}'.trim()).toSet();
  final gradable = exercises.where((e) => e['type'] != 'open').toList();
  final placement = gradable.where((e) => wanted.contains(e['prompt'])).firstOrNull ?? gradable.firstOrNull;
  placement?['placement'] = true;
  return {
    'id': id,
    'title': '${d['title'] ?? ''}'.trim(),
    'minutes': ((d['minutes'] as num?)?.toInt() ?? 10).clamp(4, 20),
    'body': '${d['body'] ?? ''}'.trim(),
    'keyPoints': _texts(d['keyPoints']),
    'interviewAngle': '${d['interviewAngle'] ?? ''}'.trim(),
    'exercises': exercises,
  };
}

/// What is wrong with a module, in the terms of `docs/content-schema.md`.
/// Empty when it can be saved.
List<String> moduleProblems(Json module, List<Json> units) {
  final out = <String>[], ids = <String>{};
  if ('${module['title'] ?? ''}'.trim().isEmpty) out.add('The module has no title.');
  final lessons = [for (final u in units) ...(u['lessons'] as List).cast<Json>()];
  if (lessons.length < 6) out.add('Only ${lessons.length} lessons were written; a module needs at least 6.');
  for (final l in lessons) {
    final name = '"${l['title']}"';
    if (!ids.add('${l['id']}')) out.add('Two lessons share the id ${l['id']}.');
    if ('${l['title']}'.isEmpty) out.add('A lesson has no title.');
    if ('${l['body']}'.length <= 400) out.add('Lesson $name is too short to teach anything.');
    final ex = (l['exercises'] as List).cast<Json>();
    if (ex.length < 3) out.add('Lesson $name has ${ex.length} usable exercises; it needs 3.');
    if (!ex.any((e) => e['type'] == 'mcq')) out.add('Lesson $name has no multiple-choice question.');
    if (!ex.any((e) => e['type'] == 'open')) out.add('Lesson $name has no open exercise.');
    if (ex.where((e) => e['placement'] == true).length != 1) out.add('Lesson $name has no placement question.');
    for (final e in ex) {
      if (!ids.add('${e['id']}')) out.add('Two exercises share the id ${e['id']}.');
    }
  }
  final iq = (module['interviewQuestions'] as List? ?? const []);
  if (iq.length < 6) out.add('Only ${iq.length} interview questions have a model answer; a module needs at least 6.');
  return out;
}

class SkillBuilder {
  SkillBuilder({required this.ask, required this.home, required this.takenIds, DateTime Function()? now}) : _now = now ?? DateTime.now;

  final AskModule ask;

  /// The learner's folder (Documents\HireFly).
  final Directory home;

  /// Module ids already in use, bundled or the learner's own.
  final Set<String> takenIds;
  final DateTime Function() _now;

  /// Writes the module and returns its id. [onProgress] is told what is being
  /// written, for the screen. Nothing is saved unless the whole module passes
  /// [moduleProblems].
  Future<String> build(SkillRequest r, {void Function(String)? onProgress}) async {
    var id = skillSlug(r.skill);
    for (var n = 2; takenIds.contains(id); n++) {
      id = '${skillSlug(r.skill)}-$n';
    }
    onProgress?.call('Planning the module');
    final outline = await ask(task: 'module-outline', instructions: moduleOutlineInstructions(r), schema: moduleOutlineSchema);
    final plan = (outline['units'] as List? ?? const []).whereType<Json>().toList();
    if (plan.length < 3) throw const SkillBuildFailure('The assistant did not plan enough units. Try again with a more specific skill name.');

    final units = <Json>[];
    for (var u = 0; u < plan.length; u++) {
      onProgress?.call('Writing unit ${u + 1} of ${plan.length}: ${plan[u]['title']}');
      final draft = await ask(task: 'module-unit', instructions: moduleUnitInstructions(r, outline, u), schema: moduleUnitSchema);
      final lessons = <Json>[];
      for (final l in (draft['lessons'] as List? ?? const []).whereType<Json>()) {
        lessons.add(lessonFromDraft(l, '$id-u${u + 1}-l${lessons.length + 1}'));
      }
      units.add({'id': '$id-u${u + 1}', 'title': '${plan[u]['title']}', 'summary': '${plan[u]['summary'] ?? ''}', 'lessons': lessons});
    }

    onProgress?.call('Writing the interview answers');
    final answers = await ask(task: 'module-answers', instructions: moduleAnswersInstructions(r, outline), schema: moduleAnswersSchema);
    final iq = <Json>[];
    for (final a in (answers['answers'] as List? ?? const []).whereType<Json>()) {
      final prompt = '${a['prompt'] ?? ''}'.trim(), strong = '${a['strongAnswer'] ?? ''}'.trim();
      if (prompt.isNotEmpty && strong.isNotEmpty) iq.add({'id': '$id-iq-${iq.length + 1}', 'prompt': prompt, 'strongAnswer': strong});
    }

    final day = _now().toIso8601String().substring(0, 10);
    final unverified = [
      'Written by the in-app assistant on $day without web access. No outside page was opened, so product names, menus, versions, limits and prices are from the model\'s memory.',
      ..._texts(outline['unverified']),
    ];
    final module = <String, Object?>{
      'id': id,
      'title': '${outline['title'] ?? r.skill}'.trim(),
      'tagline': '${outline['tagline'] ?? ''}'.trim(),
      'claim': '${outline['claim'] ?? r.claim}'.trim(),
      'units': [for (var u = 0; u < units.length; u++) 'unit-${u + 1}.json'],
      'interviewQuestions': iq,
      'resources': const <Object>[],
      'labs': const <Object>[],
      'unverified': unverified,
    };
    final problems = moduleProblems(module, units);
    if (problems.isNotEmpty) throw SkillBuildFailure('The module was not saved. ${problems.take(3).join(' ')}');

    const enc = JsonEncoder.withIndent('  ');
    final dir = Directory('${home.path}/content/skills/$id')..createSync(recursive: true);
    for (var u = 0; u < units.length; u++) {
      File('${dir.path}/unit-${u + 1}.json').writeAsStringSync('${enc.convert(units[u])}\n');
    }
    // The module file goes last: without it the folder is ignored at start.
    File('${dir.path}/module.json').writeAsStringSync('${enc.convert(module)}\n');

    // A learner with a chosen list of skills sees only those, so add this one.
    final chosen = File('${home.path}/career/skills.json');
    if (chosen.existsSync()) {
      try {
        final j = jsonDecode(chosen.readAsStringSync());
        if (j is Json && j['modules'] is List && !(j['modules'] as List).contains(id)) {
          chosen.writeAsStringSync('${enc.convert({...j, 'modules': [...(j['modules'] as List), id]})}\n');
        }
      } on FormatException {
        // Left as it is; the learner's file is theirs.
      }
    }
    return id;
  }
}
