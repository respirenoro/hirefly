import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:project_hirefly/engine/delivery.dart';
import 'package:project_hirefly/engine/sandbox.dart';
import 'package:project_hirefly/engine/voice.dart';

void main() {
  final box = Sandbox(File('assets/content/datasets/practice.sql').readAsStringSync());

  test('the practice data loads with the documented tables', () {
    expect(box.schema.keys, containsAll(['pharmacies', 'pharmacists', 'shifts', 'assignments', 'tickets']));
    expect(box.run('SELECT COUNT(*) FROM shifts').rows.single.single, 1019);
    expect(box.schema['shifts'], containsAll(['requested_at', 'filled_at', 'status', 'cancel_reason', 'is_emergency']));
  });

  test('a mistake comes back as a message, and a write reports rows changed', () {
    expect(box.run('SELEC 1').error, isNotNull);
    expect(box.run('   ').error, isNotNull);
    expect(box.run("UPDATE shifts SET status = 'open' WHERE id = 1001").changed, 1);
    box.reset();
    expect(box.run("SELECT COUNT(*) FROM shifts WHERE status = 'open'").rows.single.single, 20);
  });

  test('long results are cut off and say so', () {
    final r = box.run('SELECT * FROM shifts', limit: 50);
    expect(r.rows.length, 50);
    expect(r.truncated, isTrue);
  });

  group('checking a query against the model query', () {
    QueryResult model() => box.run("SELECT status, COUNT(*) AS n FROM shifts GROUP BY status ORDER BY n DESC");

    test('other column names, column order and row order still match', () {
      final mine = box.run('SELECT COUNT(*) AS total, status AS s FROM shifts GROUP BY status');
      expect(compareResults(mine, model()), isNull);
    });

    test('row order matters only when the question says so', () {
      final mine = box.run('SELECT status, COUNT(*) FROM shifts GROUP BY status ORDER BY 2 ASC');
      expect(compareResults(mine, model()), isNull);
      expect(compareResults(mine, model(), ordered: true), contains('Row 1'));
    });

    test('rounding to two places is tolerated; a wrong value is not', () {
      final a = box.run('SELECT 62.5'), b = box.run('SELECT 62.501');
      expect(compareResults(a, b), isNull);
      expect(compareResults(box.run('SELECT 62.6'), b), contains('values differ'));
    });

    test('wrong shape says what is different', () {
      expect(compareResults(box.run('SELECT status FROM shifts GROUP BY status'), model()), contains('column'));
      expect(compareResults(box.run("SELECT status, 1 FROM shifts WHERE status = 'open' GROUP BY status"), model()), contains('row'));
      expect(compareResults(box.run('SELECT nope FROM shifts'), model()), contains('nope'));
    });
  });

  group('delivery', () {
    test('counts words, fillers and hedges on word boundaries', () {
      final d = analyse('Um, I think it was, like, basically fine. I just liked the likeness. You know?');
      expect(d.fillers, {'um': 1, 'like': 1, 'basically': 1, 'you know': 1});
      expect(d.hedges, {'i think': 1, 'just': 1});
      expect(d.words, 15);
    });

    test('pace needs a timed answer of some length', () {
      expect(analyse('one two three', seconds: 5).wpm, isNull);
      expect(analyse(List.filled(150, 'word').join(' '), seconds: 60).wpm, 150);
      expect(analyse(List.filled(150, 'word').join(' ')).spokenSeconds, 64);
    });

    test('pauses come from where each stretch of speech sat in the recording', () {
      // Speech at 1-5 s, 6-9 s and 15-20 s: gaps of 1 s and 6 s.
      final r = summarise('words', [(15000, 5000), (1000, 4000), (6000, 3000)]);
      expect(r.seconds, 19);
      expect(r.speechSeconds, 12);
      expect(r.longestPause, 6);
      expect(r.pauses, 1);
      expect(summarise('', []).seconds, 0);
      final d = analyse(List.filled(40, 'word').join(' '), seconds: r.seconds, longestPause: r.longestPause, pauses: r.pauses);
      expect(d.spoken, isTrue);
      expect(d.notes.any((n) => n.startsWith('Longest pause: 6')), isTrue);
    });

    test('notes flag only what is off', () {
      expect(analyse(List.filled(200, 'word').join(' '), seconds: 85).notes, isEmpty);
      expect(analyse('Too short.').notes.single, contains('Very short'));
      expect(analyse(List.filled(200, 'word').join(' '), seconds: 60).notes.single, contains('Fast'));
    });
  });
}
