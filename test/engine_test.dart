import 'package:flutter_test/flutter_test.dart';
import 'package:project_hirefly/data/content.dart';
import 'package:project_hirefly/data/db.dart';
import 'package:project_hirefly/engine/engine.dart';

Question q(String id, String category, String competency, {List<String> roles = const ['any'], int frequency = 2}) =>
    Question({'id': id, 'category': category, 'competency': competency, 'prompt': id, 'roles': roles, 'frequency': frequency});

Doc item(String id, Json data) => Doc(id, 'item', 's', {'order': 0, 'state': 'new', 'attempts': 0, 'source': 'bank', 'category': 'behavioral', 'competency': 'conflict', ...data}, DateTime(2026), DateTime(2026));

void main() {
  final bank = [
    for (final c in Content.categories)
      for (var i = 0; i < 12; i++) q('$c-$i', c, ['conflict', 'learning', 'quality', 'data'][i % 4], roles: c == 'role' ? [i.isEven ? 'qa' : 'cs'] : const ['any']),
  ];

  test('role tags come from the title', () {
    expect(roleTagsFor('QA Analyst I', ''), containsAll(['qa', 'data']));
    expect(roleTagsFor('Associate Product Owner', ''), contains('po'));
    expect(roleTagsFor('Implementation Specialist', ''), contains('implementation'));
  });

  test('a plan covers every category, grows with intensity and keeps role questions on-role', () {
    final light = pickQuestions(bank: bank, roleTags: {'qa'}, count: planSize(1), mastery: Mastery({}));
    final full = pickQuestions(bank: bank, roleTags: {'qa'}, count: planSize(5), mastery: Mastery({}));
    expect({for (final p in light) p.category}, Content.categories.toSet());
    expect(full.length, greaterThan(light.length));
    expect(full.where((p) => p.category == 'role').every((p) => p.roles.contains('qa')), isTrue);
    expect({for (final p in full) p.id}.length, full.length);
  });

  test('a competency the learner is strong in is held back', () {
    final strong = Mastery({'conflict': (9.2, 4)});
    final picks = pickQuestions(bank: bank, roleTags: {'qa'}, count: planSize(2), mastery: strong);
    final fresh = pickQuestions(bank: bank, roleTags: {'qa'}, count: planSize(2), mastery: Mastery({}));
    int conflicts(List<Question> l) => l.where((p) => p.category == 'behavioral' && p.competency == 'conflict').length;
    expect(conflicts(picks), lessThanOrEqualTo(conflicts(fresh)));
    expect(picks.where((p) => p.category == 'behavioral').first.competency, isNot('conflict'));
  });

  test('mastery needs three strong answers before it counts as strong', () {
    var m = Mastery({});
    m = m.add('data', 9).add('data', 9);
    expect(m.strong('data'), isFalse);
    expect(m.add('data', 9).strong('data'), isTrue);
    expect(m.add('data', 2).strong('data'), isFalse);
  });

  test('trimming drops only untouched, non-core questions, never more than a third', () {
    final m = Mastery({'conflict': (9, 3)});
    final items = [
      item('a', {}),
      item('b', {'state': 'drafted'}),
      item('c', {'category': 'self'}),
      item('d', {'competency': 'learning'}),
      item('e', {'source': 'tailored'}),
      item('f', {}),
      item('g', {}),
    ];
    final drop = trimmable(items, m);
    expect(drop, ['a', 'f']);
  });

  test('a weak answer comes back today, a strong one later, capped at two weeks', () {
    final now = DateTime(2026, 11, 11, 10);
    final weak = afterAttempt({'attempts': 0}, 3, now);
    final good = afterAttempt({'attempts': 0}, 9.5, now);
    expect(isDue(weak, now), isTrue);
    expect(isDue(good, now), isFalse);
    expect(DateTime.parse(good['due'] as String).difference(now).inDays, inInclusiveRange(1, 14));
    expect(good['best'], 9.5);
    final worse = afterAttempt({...good}, 6, now.add(const Duration(days: 3)));
    expect(worse['best'], 9.5);
    expect(worse['last'], 6);
    expect(worse['attempts'], 2);
  });

  test('the practice queue puts never-answered first, then the weakest, and leaves out what is not due', () {
    final now = DateTime(2026, 11, 11);
    final later = now.add(const Duration(days: 5)).toIso8601String();
    final queue = drillQueue([
      item('ok', {'attempts': 1, 'last': 7.0, 'due': now.toIso8601String()}),
      item('weak', {'attempts': 2, 'last': 3.0, 'due': now.toIso8601String()}),
      item('new', {}),
      item('notdue', {'attempts': 1, 'last': 9.0, 'due': later}),
      item('skipped', {'state': 'skipped'}),
    ], now);
    expect([for (final d in queue) d.id], ['new', 'weak', 'ok']);
  });

  test('progress and rating', () {
    expect(sessionProgress([], []), 0);
    expect(sessionRating([{'state': 'new'}], []), isNull);
    final items = <Json>[
      {'state': 'ready', 'best': 8.0},
      {'state': 'new'},
      {'state': 'skipped'},
    ];
    expect(sessionProgress(items, []), closeTo(.85 * .5, 1e-9));
    expect(sessionProgress(items, [{'endedAt': 'x'}]), closeTo(.85 * .5 + .15, 1e-9));
    expect(sessionRating(items, [{'score': 6.0}]), 7.0);
  });
}
