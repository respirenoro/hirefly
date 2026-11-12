// A made-up candidate for the end-to-end tests, so they never depend on (or
// reveal) a real person's record.
import 'dart:convert';
import 'dart:io';

Directory fixtureUser() {
  final dir = Directory.systemTemp.createTempSync('hirefly_fixture_');
  void put(String path, Object body) => File('${dir.path}/$path')
    ..createSync(recursive: true)
    ..writeAsStringSync(body is String ? body : jsonEncode(body));
  put('career/facts.md', '''
# Candidate facts and rules

Jordan Example. Project coordinator at Northstar Software (2024 to 2026), which makes scheduling
and dispatch software for clinics. Wrote tickets and test cases, ran release testing, rewrote the
help centre (support tickets fell about 35 percent). Intermediate SQL for reporting. Never say:
any certification, database administration.
${List.filled(60, 'Voice: plain verbs, varied sentence length, no jargon.').join('\n')}
''');
  put('career/dossier.md', '''
# Know your role

## The business, in one minute

Clinics need shifts filled. Northstar's software is where coordinators do that all day.

## What you were

The person every request passed through on its way in and every release on its way out.
''');
  put('career/stories.json', [
    {
      'id': 'story-alert',
      'title': 'The alert feature',
      'bestFor': ['Showing initiative'],
      'competencies': ['initiative', 'ownership', 'customer-focus', 'stakeholders', 'leadership', 'problem-solving'],
      'situation': 'Coordinators kept asking who could cover an urgent shift right now.',
      'task': 'Nobody assigned it to me. I took it on.',
      'action': 'I brought the idea to the developers, scoped it with them and stayed with it to release.',
      'result': 'Clinics can now alert nearby staff, who confirm they are free.',
      'open': ['How long it took from proposal to release.'],
    },
    {
      'id': 'story-docs',
      'title': 'The help centre rewrite',
      'bestFor': ['Improving a process'],
      'competencies': ['process-improvement', 'data', 'communication', 'quality', 'learning', 'prioritization', 'teamwork', 'attention-to-detail', 'adaptability'],
      'situation': 'Support tickets kept circling the same few problems.',
      'task': 'Find the real cause.',
      'action': 'I sorted the tickets and found people did not understand features that worked, so I rewrote the help centre.',
      'result': 'Tickets fell by about 35 percent.',
      'open': <String>[],
    },
    {'id': 'story-conflict', 'title': 'A disagreement', 'bestFor': ['Conflict'], 'competencies': ['conflict'], 'situation': '', 'task': '', 'action': '', 'result': '', 'open': ['A real disagreement.']},
  ]);
  return dir;
}
