import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:project_hirefly/data/content.dart';
import 'package:project_hirefly/data/db.dart';
import 'package:project_hirefly/engine/inbox.dart';
import 'package:project_hirefly/engine/intake.dart';
import 'package:project_hirefly/ui/extras.dart';

String page({String body = ''}) => '<html><head><title>Jobs</title><script type="application/ld+json">${jsonEncode({
      '@graph': [
        {'@type': 'WebSite', 'name': 'x'},
        {
          '@type': 'JobPosting',
          'title': 'QA Analyst',
          'hiringOrganization': {'name': 'Acme Health'},
          'jobLocationType': 'TELECOMMUTE',
          'description': '<p>Test releases.</p><ul><li>Write test cases</li><li>Query with SQL</li></ul><p>${List.filled(30, 'More detail about the role.').join(' ')}</p>',
        },
      ],
    })}</script></head><body><nav>Home Careers</nav>$body</body></html>';

SkillModule module(String id) {
  final m = jsonDecode(File('assets/content/skills/$id/module.json').readAsStringSync()) as Json;
  return SkillModule(m, [for (final f in m['units'] as List) Unit(jsonDecode(File('assets/content/skills/$id/$f').readAsStringSync()) as Json)]);
}

void main() {
  group('a posting from a web page', () {
    test('structured job data wins over the page around it', () {
      final got = parsePosting(page(body: '<main>Cookie banner and unrelated text</main>'));
      expect(got.title, 'QA Analyst');
      expect(got.company, 'Acme Health');
      expect(got.text, contains('- Write test cases'));
      expect(got.text, contains('Location type: TELECOMMUTE'));
      expect(got.text, isNot(contains('Cookie banner')));
    });

    test('without it, the main text is taken and navigation dropped', () {
      final got = parsePosting('<html><head><title>Support Analyst | Acme</title></head><body><nav>Home</nav><main><h1>Support Analyst</h1><p>Triage tickets.</p><script>var x=1</script></main><footer>Legal</footer></body></html>');
      expect(got.title, 'Support Analyst | Acme');
      expect(got.text, 'Support Analyst\nTriage tickets.');
    });

    test('downloading: a good page, a refusal, an empty shell, a bad address', () async {
      final ok = MockClient((_) async => http.Response(page(), 200, headers: {'content-type': 'text/html; charset=utf-8'}));
      expect((await fetchPosting('https://example.com/job', client: ok)).title, 'QA Analyst');
      expect(() => fetchPosting('https://example.com/job', client: MockClient((_) async => http.Response('no', 403))), throwsA(isA<IntakeFailure>().having((e) => e.message, 'message', contains('refused'))));
      expect(() => fetchPosting('https://example.com/job', client: MockClient((_) async => http.Response('<html><body><div id="root"></div></body></html>', 200))),
          throwsA(isA<IntakeFailure>().having((e) => e.message, 'message', contains('no readable posting'))));
      expect(() => fetchPosting('example.com/job'), throwsA(isA<IntakeFailure>()));
      expect(() => fetchPosting('file:///C:/secret.txt'), throwsA(isA<IntakeFailure>()));
    });
  });

  group('which skills a role calls for', () {
    test('named tools outrank general wording, and one repeated word cannot carry a skill', () {
      final skills = skillsFor({'role': 'UAT Analyst', 'posting': 'Run UAT in Azure DevOps Test Plans. Write test cases. Use SQL and Excel. Log defects in Jira. ${List.filled(40, 'You will support the support team.').join(' ')}'});
      final ids = [for (final (id, _) in skills) id];
      expect(ids.first, 'ado-test-plans');
      expect(ids, containsAll(['sql', 'excel', 'jira', 'azure-devops']));
      expect(ids.indexOf('jira'), lessThan(ids.indexOf('ticket-process')));
    });

    test('a single passing hint is not enough; nothing matches an unrelated posting', () {
      expect(skillsFor({'role': 'Barista', 'posting': 'Make coffee and support the team.'}), isEmpty);
      expect([for (final (id, _) in skillsFor({'role': 'Analyst', 'posting': 'Build dashboards in Power BI.'})) id], ['power-bi']);
    });

    test('word starts are respected: "sequel" is not SQL, "adopt" is not ADO', () {
      expect(skillsFor({'role': 'Writer', 'posting': 'Write the sequel. Adopt our tone. Mysql is not mentioned? It is: mysql.'}).map((s) => s.$1), ['sql']);
    });
  });

  group('the inbox', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('hirefly_inbox_test_'));
    tearDown(() => dir.deleteSync(recursive: true));
    File write(String name, Object body) => File('${dir.path}/$name')..writeAsStringSync(body is String ? body : jsonEncode(body));

    test('text and files are read; a resume in HTML becomes its text', () async {
      final resume = write('resume.html', '<html><body><style>p{}</style><h1>Jane</h1><ul><li>Tested releases</li></ul></body></html>');
      final r = await readInboxFile(write('a.json', {'role': ' QA Analyst ', 'company': 'Acme', 'url': 'https://example.com/j', 'resumeFile': resume.path, 'interviewDate': '2026-11-20', 'intensity': 9}));
      expect(r.fields['role'], 'QA Analyst');
      expect(r.fields['resume'], 'Jane\n- Tested releases');
      expect(r.fields['intensity'], 5);
      expect(r.fields['interviewDate'], '2026-11-20');
      expect(r.url, 'https://example.com/j', reason: 'no posting text, so the address is fetched');
      expect((await readInboxFile(write('b.json', {'role': 'X', 'posting': 'text', 'url': 'https://example.com/j'}))).url, isNull);
    });

    test('a request that cannot be used says why', () async {
      expect(() => readInboxFile(write('c.json', {'company': 'Acme'})), throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('"role"'))));
      expect(() => readInboxFile(write('d.json', {'role': 'X', 'interviewDate': 'next Tuesday'})), throwsA(isA<FormatException>()));
      expect(() => readInboxFile(write('e.json', {'role': 'X', 'resumeFile': '${dir.path}/missing.html'})), throwsA(isA<IntakeFailure>()));
      expect(() => readInboxFile(write('f.json', '[1, 2]')), throwsA(isA<FormatException>()));
      expect(() => readInboxFile(write('g.json', '{"role": ')), throwsA(isA<FormatException>()));
    });

    test('a handled file is moved aside, with the reason when it failed', () async {
      final f = write('h.json', '{}');
      await shelve(f, 'failed', note: 'why');
      expect(f.existsSync(), isFalse);
      final moved = Directory('${dir.path}/failed').listSync().map((e) => e.path).toList();
      expect(moved.length, 2);
      expect(moved.any((p) => p.endsWith('.error.txt')), isTrue);
    });
  });

  test('every module has course advice, and the plan follows the days left', () {
    for (final id in Content.moduleIds) {
      final m = module(id);
      final path = m.pathway;
      expect(path, isNotNull, reason: id);
      expect('${path!['summary']}', isNotEmpty);
      expect((path['hireflyBetter'] as List).length, inInclusiveRange(3, 5), reason: id);
      expect((path['externalBetter'] as List).length, inInclusiveRange(3, 5), reason: id);
      expect((path['plans'] as List).length, 3, reason: id);
      expect(planFor(m, 2)!['hours'], lessThan((planFor(m, 10)!['hours'] as num)), reason: id);
      expect(planFor(m, 60)!['hours'], greaterThan((planFor(m, 10)!['hours'] as num)), reason: id);
      expect(planFor(m, null), planFor(m, 10));
      for (final r in m.resources) {
        expect(const ['core', 'worthwhile', 'optional'], contains(r['priority']), reason: '$id ${r['title']}');
        expect('${r['useWhen']}', isNotEmpty);
        expect('${r['versus']}', isNotEmpty);
      }
      expect(m.resources.where((r) => r['priority'] == 'core').length, lessThanOrEqualTo(3), reason: id);
    }
  });

  test('wheel-button scrolling: a dead zone, then faster with distance, capped', () {
    expect(middleScrollSpeed(0), 0);
    expect(middleScrollSpeed(10), 0);
    expect(middleScrollSpeed(-10), 0);
    expect(middleScrollSpeed(40), greaterThan(0));
    expect(middleScrollSpeed(-40), -middleScrollSpeed(40));
    expect(middleScrollSpeed(200), greaterThan(middleScrollSpeed(60) * 3));
    expect(middleScrollSpeed(5000), 9000);
  });
}
