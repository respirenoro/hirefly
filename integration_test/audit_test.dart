// The audit run: every assistant-backed feature, the inbox, loading a posting
// from an address, and a screenshot of each screen.
//
// The Claude API is replaced by a local server that checks every request is
// shaped the way the API requires (headers, cached system prefix, alternating
// turns, strict schemas) and answers with data that fits the requested
// schema. So this proves the app's side of each flow, not the model's answers.
//
// Screenshots go to the folder in HIREFLY_SHOTS (default: the system temp
// folder, under hirefly_shots).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:project_hirefly/ai/ai_client.dart';
import 'package:project_hirefly/data/content.dart';
import 'package:project_hirefly/data/db.dart';
import 'package:project_hirefly/engine/inbox.dart';
import 'package:project_hirefly/main.dart';

import 'fixture.dart';
import 'package:project_hirefly/terra/speech/speech_models.dart';

/// A value that satisfies [schema], and every way the schema breaks the
/// API's rules for structured outputs (collected into [problems]).
Object? fill(Map<String, dynamic> schema, String path, List<String> problems, {required bool lastTurnSaysEnd}) {
  switch (schema['type']) {
    case 'object':
      final props = (schema['properties'] as Map).cast<String, dynamic>();
      if (schema['additionalProperties'] != false) problems.add('$path: additionalProperties must be false');
      final required = [...schema['required'] as List? ?? const []];
      if (required.length != props.length || !props.keys.every(required.contains)) problems.add('$path: every property must be required');
      return {for (final e in props.entries) e.key: fill(e.value as Map<String, dynamic>, '$path.${e.key}', problems, lastTurnSaysEnd: lastTurnSaysEnd)};
    case 'array':
      return [fill(schema['items'] as Map<String, dynamic>, '$path[]', problems, lastTurnSaysEnd: lastTurnSaysEnd)];
    case 'number':
      return 8.5;
    case 'string':
      final e = schema['enum'] as List?;
      if (e != null) return path.endsWith('.move') ? (lastTurnSaysEnd ? 'end' : 'next') : e.first;
      return switch (path.split('.').last) {
        'say' => lastTurnSaysEnd ? 'Thank you, that is everything from me.' : 'Understood. Here is my next question for you?',
        'prompt' => 'How would you test the shift roster at Acme Health before a release?',
        'competency' => 'quality',
        'verdict' => 'Clear and specific; an interviewer would follow it.',
        'improved' || 'answer' => 'At Northstar our scheduling and dispatch software coordinated contracted pharmacists to pharmacies facing staffing shortages. I rewrote the documentation and ticket inflow dropped by about 35 percent.',
        'feedback' => 'Right idea; name the column you group by.',
        'summary' => 'A QA role on a small team: test each release, write the cases, report defects clearly.',
        final k => 'Stand-in $k from the audit server.',
      };
    default:
      problems.add('$path: unsupported type ${schema['type']}');
      return null;
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('audit: every assistant flow, the inbox, a posting from an address, and screenshots', (t) async {
    final shots = Directory(Platform.environment['HIREFLY_SHOTS'] ?? p.join(Directory.systemTemp.path, 'hirefly_shots'))..createSync(recursive: true);
    final problems = <String>[];
    final tasks = <String, int>{};
    var chatCalls = 0;

    // ---- the stand-in API, and a job posting page -----------------------------
    final server = await t.runAsync(() => HttpServer.bind(InternetAddress.loopbackIPv4, 0));
    unawaited(() async {
      await for (final req in server!) {
        if (req.uri.path == '/job') {
          req.response.headers.contentType = ContentType.html;
          req.response.write('<html><head><title>Careers</title><script type="application/ld+json">${jsonEncode({
                '@context': 'https://schema.org',
                '@type': 'JobPosting',
                'title': 'UAT Analyst',
                'hiringOrganization': {'@type': 'Organization', 'name': 'Northwind Clinics'},
                'employmentType': 'FULL_TIME',
                'jobLocationType': 'TELECOMMUTE',
                'description': '<p>We are hiring a UAT Analyst.</p><ul><li>Write test cases and run user acceptance testing in Azure DevOps Test Plans.</li><li>Use SQL to check data and build reports in Excel and Power BI.</li><li>Log defects as tickets in Jira and keep documentation current.</li></ul><p>${List.filled(40, 'You will work with product owners and support.').join(' ')}</p>',
              })}</script></head><body><nav>menu</nav><main>ignored body</main></body></html>');
          await req.response.close();
          continue;
        }
        final body = jsonDecode(await utf8.decoder.bind(req).join()) as Map<String, dynamic>;
        void need(bool ok, String what) {
          if (!ok) problems.add(what);
        }

        need(req.headers.value('x-api-key') == 'audit-key', 'x-api-key header missing');
        need(req.headers.value('anthropic-version') != null, 'anthropic-version header missing');
        need(body['model'] is String && body['max_tokens'] is int, 'model or max_tokens missing');
        final system = body['system'] as List;
        need(system.isNotEmpty && (system.first as Map)['cache_control'] != null, 'the stable system block is not marked for caching');
        need(((system.first as Map)['text'] as String).length > 2000, 'the stable system block is suspiciously short');
        final msgs = (body['messages'] as List).cast<Map<String, dynamic>>();
        need(msgs.isNotEmpty && msgs.first['role'] == 'user', 'the first message must be from the user');
        for (var i = 1; i < msgs.length; i++) {
          need(msgs[i]['role'] != msgs[i - 1]['role'], 'messages must alternate (turn $i)');
        }
        need(msgs.last['role'] == 'user', 'the last message must be from the user');
        need(msgs.every((m) => '${m['content']}'.trim().isNotEmpty), 'an empty message was sent');
        final config = body['output_config'] as Map<String, dynamic>;
        need(const ['low', 'medium', 'high', 'xhigh', 'max'].contains(config['effort']), 'effort missing');
        final last = '${msgs.last['content']}';
        final format = config['format'] as Map<String, dynamic>?;
        final instructions = system.length > 1 ? '${(system[1] as Map)['text']}' : '';
        final String text;
        if (format != null) {
          need(format['type'] == 'json_schema', 'format.type');
          final before = problems.length;
          text = jsonEncode(fill(format['schema'] as Map<String, dynamic>, r'$', problems, lastTurnSaysEnd: last.contains('No questions remain')));
          if (problems.length > before) problems.add('  (in a call whose instructions start: ${instructions.substring(0, instructions.length.clamp(0, 60))})');
        } else {
          chatCalls++;
          // The story interview asks twice, then says it has enough.
          text = instructions.contains('interviewing them') ? (msgs.length >= 4 ? 'READY' : 'What exactly was yours to do there?') : 'Group by the status column first, then count. Which column would you group by?';
        }
        final key = instructions.isEmpty ? 'none' : instructions.split('\n').firstWhere((l) => l.trim().isNotEmpty).trim();
        tasks[key.substring(0, key.length.clamp(0, 48))] = (tasks[key.substring(0, key.length.clamp(0, 48))] ?? 0) + 1;
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({
          'id': 'msg_audit',
          'model': body['model'],
          'stop_reason': 'end_turn',
          'content': [
            {'type': 'text', 'text': text},
          ],
          'usage': {'input_tokens': 120, 'cache_read_input_tokens': 9000, 'cache_creation_input_tokens': 0, 'output_tokens': 300},
        }));
        await req.response.close();
      }
    }());
    final base = 'http://127.0.0.1:${server!.port}';

    // ---- the app, with an in-memory database and a temp home ------------------
    final content = await Content.load(user: fixtureUser());
    final db = AppDatabase(NativeDatabase.memory());
    final store = Store(db);
    final home = Directory.systemTemp.createTempSync('hirefly_home_');
    await store.setSetting(AiClient.settingsKey, jsonEncode(const AiSettings(claudeKey: 'audit-key').toJson()));
    final boundary = GlobalKey();
    await t.pumpWidget(RepaintBoundary(
      key: boundary,
      child: ProviderScope(overrides: [
        contentProvider.overrideWithValue(content),
        databaseProvider.overrideWithValue(db),
        speechModelDirProvider.overrideWithValue(Directory.systemTemp.createTempSync('hirefly_models_')),
        hireflyHomeProvider.overrideWithValue(home),
        aiClientProvider.overrideWith((ref) => AiClient(ref.watch(storeProvider), url: '$base/v1/messages')),
      ], child: const HireFlyApp()),
    ));
    await t.pumpAndSettle();

    var n = 0;
    Future<void> shot(String name) async {
      await t.pumpAndSettle();
      final render = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final bytes = await t.runAsync(() async {
        final image = await render.toImage(pixelRatio: 1);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        return data!.buffer.asUint8List();
      });
      File(p.join(shots.path, '${(++n).toString().padLeft(2, '0')}-$name.png')).writeAsBytesSync(bytes!);
    }

    void step(String s) => debugPrint('STEP $s');
    Future<void> settle([int ms = 500]) async {
      await t.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));
      await t.pumpAndSettle();
    }

    /// Waits for [f] to appear: assistant calls and the inbox are asynchronous.
    Future<void> until(Finder f, String what, {int seconds = 20}) async {
      for (var i = 0; i < seconds * 4; i++) {
        if (f.evaluate().isNotEmpty) return;
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 250)));
        await t.pump();
      }
      await shot('FAILED-waiting-for-${what.replaceAll(' ', '-')}');
      fail('never appeared: $what');
    }

    Future<void> tap(Finder f) async {
      FocusManager.instance.primaryFocus?.unfocus();
      await t.pumpAndSettle();
      await t.ensureVisible(f.first);
      await t.pumpAndSettle();
      await t.tap(f.first);
      await settle();
    }

    step('Today, empty');
    await shot('today-empty');

    step('load a posting from its address');
    await tap(find.text('New role'));
    await t.enterText(find.byKey(const Key('posting-url')), '$base/job');
    await tap(find.text('Load from the address'));
    await until(find.textContaining('Posting loaded'), 'the posting');
    expect(t.widget<TextField>(find.byKey(const Key('role-title'))).controller!.text, 'UAT Analyst');
    expect(t.widget<TextField>(find.byKey(const Key('role-company'))).controller!.text, 'Northwind Clinics');
    await shot('new-role-loaded-from-address');

    step('build the plan; the brief and tailored questions follow');
    await tap(find.text('Build the plan'));
    await until(find.text('What they are screening for'), 'the role brief');
    expect(find.text('Skills this role calls for'), findsOneWidget);
    final role = (await store.list('session')).single;
    final items = await store.list('item', parent: role.id);
    expect(items.where((d) => d.data['source'] == 'tailored'), isNotEmpty, reason: 'tailored questions');
    expect(items.where((d) => d.data['source'] == 'skill').length, greaterThanOrEqualTo(4), reason: 'skill questions');
    expect({for (final d in items.where((d) => d.data['source'] == 'skill')) d.data['skill']}, containsAll(['sql', 'ado-test-plans', 'jira']));
    await shot('role-overview-with-brief');
    await t.drag(find.byType(SingleChildScrollView).last, const Offset(0, -500));
    await shot('role-overview-skills');

    step('prepare: draft from history, then coach');
    await tap(find.text('Prepare'));
    await tap(find.text('Draft it from my history'));
    await until(find.textContaining('Redraft'), 'a draft');
    expect(t.widget<TextField>(find.byKey(const Key('draft'))).controller!.text, contains('Northstar'));
    await tap(find.text('Coach this answer'));
    await until(find.text('A stronger version'), 'the coach');
    await shot('prepare-coached');

    step('practice: the coach scores an answer from memory');
    await tap(find.text('Practice'));
    await shot('practice');
    await t.enterText(find.byKey(const Key('practice-answer')), 'Our software coordinated pharmacists to pharmacies. I rewrote the documentation and tickets fell by about a third.');
    await tap(find.text('Check my answer'));
    await until(find.text('Next question'), 'the scored answer');
    expect(find.text('Delivery'), findsOneWidget);
    await shot('practice-scored');

    step('mock: a live interviewer, to the end, with a debrief');
    await tap(find.text('Mock interview'));
    await shot('mock-start');
    await tap(find.text('Start a mock interview'));
    await until(find.textContaining('my next question'), 'the interviewer');
    for (var i = 0; i < 20 && find.byKey(const Key('composer')).evaluate().isNotEmpty; i++) {
      await t.enterText(find.byKey(const Key('composer')), 'Answer number ${i + 1}: I reproduced the issue and wrote it up.');
      await tap(find.text('Send'));
      await settle(700);
      if (i == 1) await shot('mock-conversation');
    }
    await until(find.text('Practise before the real one'), 'the debrief');
    await shot('mock-debrief');
    expect((await store.list('mock', parent: role.id)).single.data['score'], 8.5);

    step('a role sent by another tool through the inbox');
    final inbox = Directory(p.join(home.path, 'inbox'))..createSync(recursive: true);
    final request = File(p.join(inbox.path, 'acme.json.tmp'));
    request.writeAsStringSync(jsonEncode({
      'role': 'Support Analyst',
      'company': 'Acme Dispatch',
      'posting': 'Triage support tickets in Zendesk, write knowledge base documentation, query data with SQL.',
      'interviewDate': DateTime.now().add(const Duration(days: 2)).toIso8601String().substring(0, 10),
      'intensity': 2,
    }));
    request.renameSync(p.join(inbox.path, 'acme.json'));
    File(p.join(inbox.path, 'broken.json')).writeAsStringSync('{"company": "No Role Inc"}');
    await until(find.textContaining('Acme Dispatch'), 'the inbox role', seconds: 30);
    await settle(3000);
    expect(File(p.join(home.path, 'outbox', 'acme-dispatch-support-analyst.md')).existsSync(), isTrue);
    final summary = File(p.join(home.path, 'outbox', 'acme-dispatch-support-analyst.md')).readAsStringSync();
    expect(summary, contains('## Skills this role calls for'));
    expect(summary, contains('The ticket process'));
    expect(summary, contains('Interview in three days or less'));
    expect(Directory(p.join(inbox.path, 'done')).listSync().length, 1);
    expect(Directory(p.join(inbox.path, 'failed')).listSync().where((f) => f.path.endsWith('.error.txt')).length, 1);
    await tap(find.text('Today'));
    await shot('today-with-roles');

    step('a lesson: an open exercise graded, and the tutor answers');
    await tap(find.text('Excel'));
    await shot('skill-lessons');
    await tap(find.text('Courses and advice'));
    expect(find.text('Your plan'), findsOneWidget);
    await shot('skill-course-advice');
    await tap(find.text('Labs'));
    await shot('skill-labs');
    await tap(find.text('Lessons'));
    await tap(find.text('Start'));
    await shot('lesson');
    await tap(find.text('Ask the tutor'));
    await t.enterText(find.byKey(const Key('composer')), 'Why does this work?');
    await tap(find.text('Send'));
    await until(find.textContaining('Which column would you group by'), 'the tutor');
    await shot('lesson-tutor');
    await tap(find.text('Hide the tutor'));
    final open = find.text('Check my answer');
    if (open.evaluate().isNotEmpty) {
      await t.enterText(find.ancestor(of: find.text('Write your answer'), matching: find.byType(TextField)).first, 'My worked answer.');
      await tap(open);
      await until(find.textContaining('name the column'), 'the graded exercise');
    }

    step('SQL: a query exercise checked by running it');
    await tap(find.text('SQL'));
    await tap(find.text('SQL sandbox'));
    await tap(find.text('Run'));
    await shot('sql-sandbox');

    step('stories: coverage, a check, the story interview, telling it');
    await tap(find.text('Your stories'));
    expect(find.text('Themes you can answer'), findsOneWidget);
    await shot('stories');
    await tap(find.text('The alert feature'));
    await shot('story-write');
    await tap(find.text('Check this story'));
    await until(find.text('The coach\'s read'), 'the story check');
    await tap(find.textContaining('Interview me'));
    await until(find.textContaining('What exactly was yours'), 'the story interviewer');
    await t.enterText(find.byKey(const Key('composer')), 'I brought the idea to the developers and scoped it with them.');
    await tap(find.text('Send'));
    await settle(800);
    await shot('story-interview');
    await t.enterText(find.byKey(const Key('composer')), 'It went live and staff could see who answered first.');
    await tap(find.text('Send'));
    await until(find.textContaining('Written up from your answers'), 'the written-up story');
    await tap(find.text('Questions it answers'));
    await shot('story-questions');
    await tap(find.text('Tell it'));
    await tap(find.text('Start'));
    await t.enterText(find.byKey(const Key('story-tell')), 'Coordinators kept asking who could cover a shift, so I brought the idea to the developers and scoped it.');
    await tap(find.text('Done'));
    await until(find.text('What you wrote'), 'the told story');
    await shot('story-told');

    step('know your role, settings');
    await tap(find.text('Know your role'));
    await shot('dossier');
    await tap(find.text('Settings'));
    await shot('settings');

    debugPrint('CALLS ${tasks.entries.map((e) => '${e.value}x ${e.key}').join(' | ')}');
    debugPrint('CHAT calls $chatCalls; shots in ${shots.path}');
    final spend = await store.db.select(store.db.aiCalls).get();
    debugPrint('LOGGED ${spend.length} calls, ${spend.where((c) => c.status != 'ok').length} failed, cache read ${spend.fold<int>(0, (a, c) => a + c.cacheReadTok)} tokens');
    expect(problems, isEmpty, reason: problems.join('\n'));
    expect(spend.every((c) => c.status == 'ok'), isTrue);
    expect(binding, isNotNull);
    await t.runAsync(() => server.close(force: true));
    step('done');
  });
}
