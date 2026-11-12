// The pacing engine: what goes into a role's plan, what gets dropped when the
// learner is already strong, and when a question comes back. Pure functions
// over plain maps, so they can be tested without the app.
import 'dart:math' as math;

import '../core/fsrs.dart';
import '../data/content.dart';
import '../data/db.dart';

/// Role families a posting can belong to, found from its title and text.
const _roleWords = {
  'qa': ['qa', 'quality assurance', 'tester', 'test analyst', 'uat', 'quality analyst', 'testing'],
  'ba': ['business analyst', 'systems analyst', 'requirements', 'business systems'],
  'po': ['product owner', 'product analyst', 'product manager', 'apm', 'product operations'],
  'pm': ['project coordinator', 'project manager', 'program coordinator', 'program manager', 'project analyst', 'scrum'],
  'support': ['support', 'help desk', 'service desk', 'application administrator', 'system administrator', 'technical specialist'],
  'implementation': ['implementation', 'onboarding', 'solutions', 'deployment specialist', 'training specialist'],
  'ops': ['operations', 'ops analyst', 'coordinator', 'administrator', 'assistant'],
  'data': ['data', 'reporting', 'analyst', 'sql', 'excel', 'bi '],
  'cs': ['customer success', 'account manager', 'client success', 'customer experience'],
  'healthcare': ['health', 'clinical', 'medical', 'pharmacy', 'patient', 'hospital', 'care'],
};

/// The title decides; the posting text only adds a family it mentions often.
Set<String> roleTagsFor(String title, String posting) {
  final t = title.toLowerCase(), p = posting.toLowerCase();
  final tags = <String>{};
  for (final e in _roleWords.entries) {
    if (e.value.any(t.contains)) {
      tags.add(e.key);
    } else if (e.value.fold<int>(0, (n, w) => n + w.allMatches(p).length) >= 4) {
      tags.add(e.key);
    }
  }
  return tags;
}

const intensityNames = ['', 'Light', 'Focused', 'Standard', 'Thorough', 'Exhaustive'];

/// Questions in a plan at each intensity (1-5).
int planSize(int intensity) => const [0, 10, 16, 24, 34, 46][intensity.clamp(1, 5)];

/// Follow-ups the mock interviewer asks per question, at most.
int followUpDepth(int intensity) => const [0, 0, 1, 1, 2, 3][intensity.clamp(1, 5)];

const _share = {
  'background': .09, 'motivation': .09, 'self': .09, 'behavioral': .33,
  'situational': .14, 'role': .18, 'curveball': .04, 'closing': .04, //
};

/// Competency mastery: a running score 0-10 and how many answers fed it.
class Mastery {
  Mastery(this.byCompetency);
  final Map<String, (double, int)> byCompetency;

  factory Mastery.of(Json? j) => Mastery({
        for (final e in (j ?? const {}).entries)
          if (e.value is List && (e.value as List).length == 2)
            e.key: (((e.value as List)[0] as num).toDouble(), ((e.value as List)[1] as num).toInt()),
      });

  Json toJson() => {for (final e in byCompetency.entries) e.key: [e.value.$1, e.value.$2]};

  double? score(String c) => byCompetency[c]?.$1;
  bool strong(String c) => (byCompetency[c]?.$1 ?? 0) >= 8.5 && (byCompetency[c]?.$2 ?? 0) >= 3;

  /// Recent answers count for more than old ones.
  Mastery add(String c, double score) {
    final (ema, n) = byCompetency[c] ?? (0.0, 0);
    return Mastery({...byCompetency, c: (n == 0 ? score : ema * .6 + score * .4, n + 1)});
  }
}

int _jitter(String id) => id.codeUnits.fold(7, (h, c) => (h * 31 + c) & 0xffff) % 100;

/// Picks [count] bank questions for a role. Common questions and the
/// learner's weak competencies come first; competencies they are already
/// strong in are held back unless the bank runs out.
List<Question> pickQuestions({
  required List<Question> bank,
  required Set<String> roleTags,
  required int count,
  required Mastery mastery,
  Set<String> exclude = const {},
}) {
  double score(Question q) {
    final roleFit = q.roles.any(roleTags.contains) ? 3.0 : (q.roles.contains('any') ? 1.0 : -100.0);
    final weak = (10 - (mastery.score(q.competency) ?? 6)) / 3;
    return q.frequency * 2 + roleFit + weak - (mastery.strong(q.competency) ? 4 : 0) + _jitter(q.id) / 100;
  }

  final picked = <Question>[];
  for (final cat in Content.categories) {
    final pool = bank.where((q) => q.category == cat && !exclude.contains(q.id) && score(q) > -50).toList()
      ..sort((a, b) => score(b).compareTo(score(a)));
    final want = math.max(1, (count * (_share[cat] ?? .05)).round());
    // Spread across competencies before taking a second from any one.
    final seen = <String, int>{};
    final rank = {for (final q in pool) q.id: seen.update(q.competency, (n) => n + 1, ifAbsent: () => 0)};
    final ordered = [...pool]..sort((a, b) {
        final r = rank[a.id]!.compareTo(rank[b.id]!);
        return r != 0 ? r : score(b).compareTo(score(a));
      });
    picked.addAll(ordered.take(want));
  }
  return picked;
}

/// A plan item made from a bank question.
Json itemFromQuestion(Question q, int order, {String? draft}) => {
      'order': order,
      'qid': q.id,
      'prompt': q.prompt,
      'category': q.category,
      'competency': q.competency,
      'intent': q.intent,
      'framework': q.framework,
      'guide': q.answerGuide,
      'pitfalls': q.pitfalls,
      'followUps': q.followUps,
      'source': 'bank',
      'draft': draft ?? '',
      'state': (draft ?? '').trim().isEmpty ? 'new' : 'drafted',
      'attempts': 0,
    };

bool isActive(Json item) => item['state'] != 'skipped';
double? bestOf(Json item) => (item['best'] as num?)?.toDouble();

/// How far along one question is, 0-1: drafted, marked ready, then answered
/// from memory well enough.
double itemProgress(Json item) {
  final best = bestOf(item);
  if (best != null && best >= 7) return 1;
  if (best != null && best >= 5) return .8;
  return switch (item['state']) { 'ready' => .6, 'drafted' => .3, _ => (item['attempts'] as int? ?? 0) > 0 ? .4 : 0 };
}

/// Estimated completion for a role, 0-1. The mock interview is the last 15%.
double sessionProgress(List<Json> items, List<Json> mocks) {
  final active = items.where(isActive).toList();
  if (active.isEmpty) return 0;
  final prep = active.fold<double>(0, (a, i) => a + itemProgress(i)) / active.length;
  final mock = mocks.any((m) => m['debrief'] != null || m['endedAt'] != null) ? 1.0 : 0.0;
  return prep * .85 + mock * .15;
}

/// Overall performance so far, 0-10, or null before any answer is scored.
double? sessionRating(List<Json> items, List<Json> mocks) {
  final scores = [for (final i in items) ?bestOf(i)];
  final mockScores = [for (final m in mocks) ?(m['score'] as num?)?.toDouble()];
  if (scores.isEmpty && mockScores.isEmpty) return null;
  final prep = scores.isEmpty ? null : scores.reduce((a, b) => a + b) / scores.length;
  final mock = mockScores.isEmpty ? null : mockScores.last;
  if (prep == null) return mock;
  if (mock == null) return prep;
  return (prep + mock) / 2;
}

/// Questions to drop because the learner has already shown the competency:
/// untouched, not one of the questions every interview asks, and in a
/// competency scored 8.5+ at least three times. Never more than a third.
List<String> trimmable(List<Doc> items, Mastery mastery) {
  const always = {'background', 'motivation', 'self', 'closing'};
  final active = items.where((d) => isActive(d.data)).toList();
  final out = [
    for (final d in active)
      if (d.data['state'] == 'new' &&
          (d.data['attempts'] as int? ?? 0) == 0 &&
          d.data['source'] == 'bank' &&
          !always.contains(d.data['category']) &&
          mastery.strong(d.data['competency'] as String))
        d.id,
  ];
  return out.take(active.length ~/ 3).toList();
}

final _fsrs = Fsrs(fsrsDefaultWeights);

/// 1 Again, 2 Hard, 3 Good, 4 Easy, from a 0-10 score.
int ratingFor(double score) => score < 5 ? 1 : (score < 7 ? 2 : (score < 8.5 ? 3 : 4));

/// The fields to merge into an item after an answer scored [score]: its best
/// and last score, and when it should come back (FSRS, capped at two weeks
/// because an interview is near).
Json afterAttempt(Json item, double score, DateTime now) {
  final rating = ratingFor(score);
  final s0 = (item['s'] as num?)?.toDouble(), d0 = (item['d'] as num?)?.toDouble();
  final last = DateTime.tryParse(item['lastAt'] as String? ?? '');
  double s, d;
  if (s0 == null || d0 == null || last == null) {
    s = _fsrs.initialStability(rating);
    d = _fsrs.initialDifficulty(rating, clamp: true);
  } else {
    final days = now.difference(last).inDays;
    s = days == 0 ? _fsrs.shortTermStability(s0, rating) : _fsrs.nextStability(d0, s0, _fsrs.retrievability(days, s0), rating);
    d = _fsrs.nextDifficulty(d0, rating);
  }
  final days = rating == 1 ? 0 : _fsrs.nextInterval(s, .9, 14);
  return {
    's': s,
    'd': d,
    'lastAt': now.toIso8601String(),
    'due': now.add(Duration(days: days)).toIso8601String(),
    'last': score,
    'best': math.max(score, bestOf(item) ?? 0),
    'attempts': (item['attempts'] as int? ?? 0) + 1,
  };
}

bool isDue(Json item, DateTime now) {
  final due = DateTime.tryParse(item['due'] as String? ?? '');
  return due == null || !due.isAfter(now);
}

/// The order to practise in: never answered first, then what is due with the
/// weakest last score first. Questions answered well and not yet due are left out.
List<Doc> drillQueue(List<Doc> items, DateTime now) {
  final pool = items.where((d) => isActive(d.data) && isDue(d.data, now)).toList();
  double key(Doc d) => (d.data['attempts'] as int? ?? 0) == 0 ? -1 : ((d.data['last'] as num?)?.toDouble() ?? 0);
  pool.sort((a, b) {
    final k = key(a).compareTo(key(b));
    return k != 0 ? k : (a.data['order'] as int).compareTo(b.data['order'] as int);
  });
  return pool;
}
