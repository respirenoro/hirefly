// What happens to a role's prep session: making it, building its brief,
// scoring answers, and changing its pace.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

import '../ai/ai_client.dart';
import '../ai/prompts.dart';
import '../data/content.dart';
import '../data/db.dart';
import 'engine.dart';
import 'intake.dart';

/// The readable text of a resume file (.html, .md or .txt).
Future<String> readResumeFile(String path) async {
  final raw = await File(path).readAsString();
  if (!path.toLowerCase().endsWith('.html') && !path.toLowerCase().endsWith('.htm')) return raw.trim();
  final doc = html.parse(raw);
  doc.querySelectorAll('style,script').forEach((e) => e.remove());
  for (final e in doc.querySelectorAll('p,div,li,h1,h2,h3,h4,tr,br,section')) {
    e.append(dom.Text('\n'));
  }
  return (doc.body?.text ?? '').split('\n').map((l) => l.replaceAll(RegExp(r'\s+'), ' ').trim()).where((l) => l.isNotEmpty).join('\n');
}

class Sessions {
  Sessions(this._store, this._content, this._ai, this._stories);
  final Store _store;
  final Content _content;
  final AiClient _ai;
  final Future<List<Json>> Function() _stories;

  static const masteryKey = 'mastery';

  Future<Mastery> mastery() async {
    final raw = await _store.setting(masteryKey);
    return Mastery.of(raw == null ? null : jsonDecode(raw) as Json);
  }

  /// The learner's saved answer to a bank question, reused across roles.
  Future<String?> _savedAnswer(String qid) async => (await _store.get('ans-$qid'))?.data['text'] as String?;

  Future<String> create(Json session) async {
    final id = await _store.put('session', {...session, 'status': 'active'});
    final tags = roleTagsFor(session['role'] as String, session['posting'] as String? ?? '');
    final picks = pickQuestions(bank: _content.questions, roleTags: tags, count: planSize(session['intensity'] as int), mastery: await mastery());
    var order = 0;
    for (final q in picks) {
      await _store.put('item', itemFromQuestion(q, order++, draft: await _savedAnswer(q.id)), parent: id);
    }
    // Questions on the tools the posting names, with their model answers.
    final perSkill = const [0, 1, 2, 2, 3, 4][(session['intensity'] as int).clamp(1, 5)];
    for (final item in skillItems(_content, session, perSkill: perSkill, startOrder: order)) {
      await _store.put('item', {...item, 'draft': await _savedAnswer(item['qid'] as String) ?? ''}, parent: id);
    }
    return id;
  }

  Future<String> _context(Json session) async => sessionContext(_content, await _stories(), session);

  /// Writes the role brief and adds the questions specific to this posting.
  Future<void> buildBrief(Doc session) async {
    final items = await _store.list('item', parent: session.id);
    final count = (planSize(session.data['intensity'] as int) / 4).round().clamp(3, 10);
    final r = await _ai.structured(
      task: 'brief',
      stable: await _context(session.data),
      instructions: briefInstructions(count, [for (final i in items) i.data['prompt'] as String]),
      turns: const [AiTurn.user('Write the brief and the tailored questions.')],
      schema: briefSchema,
      effort: 'high',
    );
    final tailored = (r.remove('tailored') as List? ?? const []).cast<Json>();
    await _store.patch(session.id, {'brief': r});
    var order = items.fold<int>(0, (m, i) => (i.data['order'] as int) >= m ? (i.data['order'] as int) + 1 : m);
    for (final t in tailored) {
      await _store.put(
        'item',
        {
          'order': order++,
          'prompt': t['prompt'],
          'category': t['category'],
          'competency': t['competency'],
          'intent': t['intent'],
          'framework': 'STAR',
          'guide': t['guide'],
          'pitfalls': const <String>[],
          'followUps': t['followUps'],
          'source': 'tailored',
          'draft': '',
          'state': 'new',
          'attempts': 0,
        },
        parent: session.id,
      );
    }
  }

  /// Saves a brief written elsewhere (a Claude session, when the app has no
  /// key) and adds its tailored questions. Missing lists become empty, so a
  /// partial brief still shows.
  Future<void> applyBrief(String sessionId, Json? brief, List tailored) async {
    if (brief != null) {
      List list(String k) => brief[k] is List ? brief[k] as List : const [];
      await _store.patch(sessionId, {
        'brief': {
          'summary': '${brief['summary'] ?? ''}',
          'whatTheyWant': [for (final x in list('whatTheyWant')) '$x'],
          'yourEdge': [for (final x in list('yourEdge')) if (x is Map) {'point': '${x['point'] ?? ''}', 'evidence': '${x['evidence'] ?? ''}'}],
          'gaps': [for (final x in list('gaps')) if (x is Map) {'gap': '${x['gap'] ?? ''}', 'howToAnswer': '${x['howToAnswer'] ?? ''}'}],
          'whyThisCompany': '${brief['whyThisCompany'] ?? ''}',
          'questionsToAsk': [for (final x in list('questionsToAsk')) '$x'],
        },
      });
    }
    final items = await _store.list('item', parent: sessionId);
    final have = {for (final i in items) '${i.data['prompt']}'.toLowerCase().trim()};
    var order = items.fold<int>(0, (m, i) => (i.data['order'] as int) >= m ? (i.data['order'] as int) + 1 : m);
    for (final t in tailored.whereType<Map>()) {
      final prompt = '${t['prompt'] ?? ''}'.trim();
      if (prompt.isEmpty || !have.add(prompt.toLowerCase())) continue;
      final cat = '${t['category'] ?? 'role'}';
      await _store.put(
        'item',
        {
          'order': order++,
          'prompt': prompt,
          'category': Content.categories.contains(cat) ? cat : 'role',
          'competency': '${t['competency'] ?? 'technical-knowledge'}',
          'intent': '${t['intent'] ?? ''}',
          'framework': 'STAR',
          'guide': [for (final g in t['guide'] is List ? t['guide'] as List : const []) '$g'],
          'pitfalls': const <String>[],
          'followUps': [for (final g in t['followUps'] is List ? t['followUps'] as List : const []) '$g'],
          'source': 'tailored',
          'draft': '',
          'state': 'new',
          'attempts': 0,
        },
        parent: sessionId,
      );
    }
  }

  /// Saves a coach's read of an answer that was written elsewhere.
  Future<bool> applyCoach(String itemId, Json eval) async {
    final item = await _store.get(itemId);
    if (item == null || item.kind != 'item' || eval['score'] is! num) return false;
    List<String> list(String k) => [for (final x in eval[k] is List ? eval[k] as List : const []) '$x'];
    await _store.patch(itemId, {
      'coach': {
        'score': (eval['score'] as num).toDouble().clamp(0, 10),
        'verdict': '${eval['verdict'] ?? ''}',
        'strengths': list('strengths'),
        'fixes': list('fixes'),
        'missing': list('missing'),
        'overclaims': list('overclaims'),
        'improved': '${eval['improved'] ?? ''}',
        'followUp': '${eval['followUp'] ?? ''}',
      },
    });
    return true;
  }

  Future<Json> draft(Doc session, Doc item) async => _ai.structured(
        task: 'draft',
        stable: await _context(session.data),
        instructions: draftInstructions,
        turns: [AiTurn.user(jsonEncode({'question': item.data['prompt'], 'whatTheInterviewerIsChecking': item.data['intent'], 'candidateNotesSoFar': item.data['draft']}))],
        schema: draftSchema,
      );

  Future<Json> coach(Doc session, Doc item, String answer, {required String mode}) async => _ai.structured(
        task: 'coach-$mode',
        stable: await _context(session.data),
        instructions: coachInstructions,
        turns: [AiTurn.user(coachUser(item.data, answer, mode: mode))],
        schema: coachSchema,
      );

  /// Saves a draft. A ready answer to a bank question is also kept for other roles.
  Future<void> saveDraft(Doc item, String text, {bool? ready}) async {
    final state = item.data['state'] == 'skipped'
        ? 'skipped'
        : (ready ?? item.data['state'] == 'ready') && text.trim().isNotEmpty
            ? 'ready'
            : (text.trim().isEmpty ? 'new' : 'drafted');
    await _store.patch(item.id, {'draft': text, 'state': state});
    final qid = item.data['qid'] as String?;
    if (state == 'ready' && qid != null) await _store.put('answer', {'text': text}, id: 'ans-$qid');
  }

  /// Records a scored answer. Returns how many untouched questions were
  /// dropped from the plan because the learner is already strong there.
  Future<int> recordAttempt(Doc item, {required double score, required String mode, required String answer, Json? eval}) async {
    final sessionId = item.parent!;
    await _store.put('attempt', {'sessionId': sessionId, 'mode': mode, 'answer': answer, 'score': score, 'eval': eval, 'at': nowUtc().toIso8601String()}, parent: item.id);
    await _store.patch(item.id, afterAttempt(item.data, score, DateTime.now()));
    final m = (await mastery()).add(item.data['competency'] as String, score);
    await _store.setSetting(masteryKey, jsonEncode(m.toJson()));
    final drop = trimmable(await _store.list('item', parent: sessionId), m);
    for (final id in drop) {
      await _store.patch(id, {'state': 'skipped', 'skipReason': 'strong'});
    }
    return drop.length;
  }

  Future<void> setSkipped(Doc item, bool skipped) => _store.patch(item.id, {
        'state': skipped ? 'skipped' : ('${item.data['draft']}'.trim().isEmpty ? 'new' : 'drafted'),
        'skipReason': skipped ? 'you' : null,
      });

  /// Dials a role's plan up or down. Going down drops untouched questions
  /// from the end; going up brings those back first, then adds new ones.
  Future<void> setIntensity(Doc session, int intensity) async {
    intensity = intensity.clamp(1, 5);
    await _store.patch(session.id, {'intensity': intensity});
    final items = await _store.list('item', parent: session.id);
    final bank = items.where((d) => d.data['source'] == 'bank').toList();
    final active = bank.where((d) => isActive(d.data)).toList();
    final want = planSize(intensity);
    if (active.length > want) {
      const always = {'background', 'motivation', 'self', 'closing'};
      final droppable = active.reversed.where((d) => d.data['state'] == 'new' && (d.data['attempts'] as int? ?? 0) == 0 && !always.contains(d.data['category']));
      for (final d in droppable.take(active.length - want)) {
        await _store.patch(d.id, {'state': 'skipped', 'skipReason': 'pace'});
      }
    } else if (active.length < want) {
      var need = want - active.length;
      for (final d in bank.where((d) => d.data['skipReason'] == 'pace').take(need)) {
        await _store.patch(d.id, {'state': '${d.data['draft']}'.trim().isEmpty ? 'new' : 'drafted', 'skipReason': null});
        need--;
      }
      if (need <= 0) return;
      final have = {for (final d in bank) d.data['qid'] as String};
      final more = pickQuestions(
        bank: _content.questions,
        roleTags: roleTagsFor(session.data['role'] as String, session.data['posting'] as String? ?? ''),
        count: want,
        mastery: await mastery(),
        exclude: have,
      );
      var order = items.fold<int>(0, (m, i) => (i.data['order'] as int) >= m ? (i.data['order'] as int) + 1 : m);
      for (final q in more.take(need)) {
        await _store.put('item', itemFromQuestion(q, order++, draft: await _savedAnswer(q.id)), parent: session.id);
      }
    }
  }

  // ---- Mock interview -------------------------------------------------------

  Future<Json> interviewerTurn(Doc session, List<Json> turns, {required String director, required int maxFollowUps}) async {
    final msgs = <AiTurn>[
      for (final t in turns) AiTurn(t['role'] == 'user' ? 'user' : 'assistant', t['text'] as String),
    ];
    // The app's stage direction rides on the last user turn, so roles alternate.
    final lastUser = msgs.isNotEmpty && msgs.last.role == 'user' ? msgs.removeLast().text : 'I am ready to begin.';
    msgs.add(AiTurn.user('$lastUser\n\n[App, not the candidate: $director]'));
    // The API needs a user turn first; the transcript opens with the interviewer.
    if (msgs.first.role == 'assistant') msgs.insert(0, const AiTurn.user('I am ready to begin.'));
    return _ai.structured(
      task: 'mock-turn',
      stable: await _context(session.data),
      instructions: interviewerInstructions(session.data, maxFollowUps),
      turns: msgs,
      schema: interviewerSchema,
      effort: 'low',
    );
  }

  Future<Json> debrief(Doc session, List<Json> turns) async => _ai.structured(
        task: 'mock-debrief',
        stable: await _context(session.data),
        instructions: debriefInstructions,
        turns: [AiTurn.user([for (final t in turns) '${t['role'] == 'user' ? 'CANDIDATE' : 'INTERVIEWER'}: ${t['text']}'].join('\n\n'))],
        schema: debriefSchema,
        effort: 'high',
      );
}

/// Not auto-disposed: a call started on one screen must finish after the
/// learner has moved to another.
final sessionsProvider = Provider<Sessions>((ref) {
  final store = ref.watch(storeProvider), content = ref.watch(contentProvider);
  return Sessions(store, content, ref.watch(aiClientProvider), () => loadStories(store, content));
});
