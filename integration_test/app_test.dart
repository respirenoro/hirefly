// Drives the real app, without a key, through one role, one lesson and the
// SQL sandbox. The database is in memory, so the learner's own data is never
// touched. Nothing here speaks aloud or writes outside the app.
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:project_hirefly/data/content.dart';
import 'package:project_hirefly/data/db.dart';
import 'package:project_hirefly/engine/engine.dart';
import 'package:project_hirefly/engine/export.dart';
import 'package:project_hirefly/engine/inbox.dart';
import 'package:project_hirefly/main.dart';

import 'fixture.dart';
import 'package:project_hirefly/terra/speech/speech_models.dart';
import 'package:project_hirefly/ui/ui.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a role from plan to mock, a lesson, the sandbox, with progress on Today', (t) async {
    void step(String s) => debugPrint('STEP $s');
    Future<void> settle() async {
      // Saves are asynchronous: give the database a moment before settling.
      await t.pump(const Duration(milliseconds: 400));
      await t.pumpAndSettle();
    }

    Future<void> tap(Finder f) async {
      // A focused field scrolls itself back into view, undoing ensureVisible.
      FocusManager.instance.primaryFocus?.unfocus();
      await t.pumpAndSettle();
      await t.ensureVisible(f.first);
      await t.pumpAndSettle();
      await t.tap(f.first);
      await settle();
    }

    final content = await Content.load(user: fixtureUser());
    final db = AppDatabase(NativeDatabase.memory());
    final store = Store(db);
    await t.pumpWidget(ProviderScope(overrides: [
      contentProvider.overrideWithValue(content),
      databaseProvider.overrideWithValue(db),
      // An empty folder: no speech model is installed in this run.
      speechModelDirProvider.overrideWithValue(Directory.systemTemp.createTempSync('hirefly_models_')),
      hireflyHomeProvider.overrideWithValue(Directory.systemTemp.createTempSync('hirefly_home_')),
    ], child: const HireFlyApp()));
    await t.pumpAndSettle();
    Future<List<Json>> items() async => [for (final d in await store.list('item')) d.data];

    step('Today shows the sidebar, nine skills and a loaded bank');
    expect(content.questions.length, greaterThan(250));
    expect(content.modules.length, 9);
    expect(find.text('Do next'), findsOneWidget);
    expect(find.text('Power BI'), findsWidgets);

    step('create a role');
    await tap(find.text('New role'));
    await t.enterText(find.byKey(const Key('role-title')), 'QA Analyst');
    await t.enterText(find.byKey(const Key('role-company')), 'Acme Health');
    await tap(find.text('Build the plan'));
    expect(find.text('0% prepared'), findsOneWidget);
    final before = (await items()).where(isActive).length;
    expect(before, inInclusiveRange(20, 26));

    step('prepare an answer; the selection stays put while it autosaves');
    await tap(find.text('Prepare'));
    expect(find.text('What they are really asking'), findsOneWidget);
    await t.enterText(find.byKey(const Key('draft')), 'At Northstar our scheduling and dispatch software coordinated contracted pharmacists to pharmacies facing staffing shortages.');
    await t.pump(const Duration(seconds: 1));
    await settle();
    expect(t.widget<TextField>(find.byKey(const Key('draft'))).controller!.text, startsWith('At Northstar'));
    await tap(find.text('Ready, next question'));
    expect((await items()).where((i) => i['state'] == 'ready').length, 1);

    step('practise from memory: timed, with delivery figures, self-rated');
    await tap(find.text('Practice'));
    await t.enterText(find.byKey(const Key('practice-answer')), 'Um, my answer from memory, basically.');
    await tap(find.text('Check my answer'));
    expect(find.text('Delivery'), findsOneWidget);
    expect(find.text('How close were you?'), findsOneWidget);
    await tap(find.text('Good'));
    expect(find.textContaining('1 done this sitting'), findsOneWidget);
    expect((await items()).where((i) => i['best'] == 8.0).length, 1);

    step('pace: too much trims the plan');
    await tap(find.text('Overview'));
    await tap(find.text('Too much'));
    expect((await items()).where(isActive).length, lessThan(before));
    expect(find.textContaining('Left out of the plan'), findsOneWidget);

    step('sit a scripted mock and rate it');
    await tap(find.text('Mock interview'));
    await tap(find.text('Start a mock interview'));
    expect(find.textContaining('Thanks for making the time'), findsOneWidget);
    await t.enterText(find.byKey(const Key('composer')), 'Here is my first answer.');
    await tap(find.text('Send'));
    expect(find.text('Here is my first answer.'), findsOneWidget);
    expect(find.textContaining('5 words'), findsOneWidget);
    await tap(find.text('End the interview'));
    expect(find.text('How did that go?'), findsOneWidget);
    await tap(find.text('Strong'));

    step('exports: the cheat sheet and the practice data are written under Documents');
    final role = (await store.list('session')).single;
    final sheet = await t.runAsync(() async => exportCheatSheet(role, await store.list('item', parent: role.id)));
    final html = sheet!.readAsStringSync();
    expect(html, contains('QA Analyst'));
    expect(html, contains('At Northstar our scheduling and dispatch software'));
    sheet.deleteSync();
    final data = await t.runAsync(exportPracticeData);
    expect(data!.parent.listSync().length, greaterThanOrEqualTo(6));

    step('Today shows the role with a rating, and what to do next');
    await tap(find.text('Today'));
    expect(find.text('Acme Health'), findsOneWidget);
    expect(find.text('0% prepared'), findsNothing);
    expect(find.byType(ScoreBadge), findsOneWidget);
    expect(find.textContaining('for Acme Health'), findsWidgets);

    step('a lesson: text is one selectable document, an exercise is answered');
    await tap(find.text('SQL'));
    await tap(find.text('Start'));
    expect(find.text('Key points'), findsOneWidget);
    expect(find.byType(SelectionArea), findsWidgets);
    expect(find.byType(SelectableText), findsNothing);
    await tap(find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key as ValueKey<String>).value.startsWith('choice-')));
    expect(find.textContaining(RegExp('Correct.|Not quite.')), findsOneWidget);
    await tap(find.text('Mark as complete'));
    expect(find.text('Lesson complete'), findsOneWidget);

    step('the module page counts it; a unit can be tested out of');
    await tap(find.text('SQL'));
    expect(find.textContaining('1 of '), findsWidgets);
    await tap(find.text('I know this: test out'));
    expect(find.textContaining('One question per lesson'), findsOneWidget);
    await tap(find.text('Cancel'));

    step('labs and courses open when the module has them');
    final sql = content.modules.firstWhere((m) => m.id == 'sql');
    if (sql.labs.isNotEmpty) {
      await tap(find.text('Labs'));
      expect(find.text('Get the practice data'), findsOneWidget);
    }
    if (sql.resources.isNotEmpty) {
      await tap(find.text('Courses and advice'));
      expect(find.textContaining('http'), findsWidgets);
    }

    step('the SQL sandbox runs a query on the practice data');
    await tap(find.text('SQL sandbox'));
    await tap(find.text('Run'));
    expect(find.text('3 rows'), findsOneWidget);
    expect(find.text('completed'), findsOneWidget);
    await t.enterText(find.byKey(const Key('sql-editor')), 'SELEC nonsense');
    await tap(find.text('Run'));
    expect(find.textContaining('syntax error'), findsOneWidget);

    step('stories and the role dossier open');
    await tap(find.text('Your stories'));
    expect(find.text('The alert feature'), findsOneWidget);
    await tap(find.text('Know your role'));
    expect(find.textContaining('The business, in one minute'), findsOneWidget);
    await tap(find.text('Settings'));
    expect(find.text('Claude API key'), findsOneWidget);
    expect(find.textContaining('Download ('), findsOneWidget);

    step('speaking without the model points to Settings instead of failing');
    await tap(find.textContaining('Acme Health'));
    await tap(find.text('Practice'));
    await tap(find.text('Speak my answer'));
    expect(find.text('Voice'), findsOneWidget);
    step('done');
  });
}
