// The inbox: a folder other tools write role requests into. HireFly turns
// each one into a role with its plan, and writes back a summary the other
// tool can read. Folder: Documents\HireFly\inbox (see docs/inbox.md).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../ai/ai_client.dart';
import '../data/content.dart';
import '../data/db.dart';
import 'engine.dart';
import 'intake.dart';
import 'sessions.dart';

/// Documents\HireFly: where the inbox, outbox and exports live. Set in `main`.
final hireflyHomeProvider = Provider<Directory>((ref) => throw UnimplementedError());

/// The pathway plan that fits the time left before the interview.
Json? planFor(SkillModule m, int? daysLeft) {
  final plans = [for (final x in (m.pathway?['plans'] as List? ?? const [])) x as Json];
  if (plans.isEmpty) return null;
  final i = daysLeft == null ? 1 : (daysLeft <= 3 ? 0 : (daysLeft <= 21 ? 1 : 2));
  return plans[i.clamp(0, plans.length - 1)];
}

int? daysLeft(Json session) {
  final d = DateTime.tryParse('${session['interviewDate'] ?? ''}');
  if (d == null) return null;
  final now = DateTime.now();
  return DateTime(d.year, d.month, d.day).difference(DateTime(now.year, now.month, now.day)).inDays;
}

/// What HireFly made of a role, as Markdown for another tool or a person.
String roleSummary(Content content, Doc session, List<Doc> items) {
  final s = session.data;
  final company = '${s['company']}'.trim();
  final active = items.where((d) => isActive(d.data)).toList()..sort((a, b) => (a.data['order'] as int).compareTo(b.data['order'] as int));
  final skills = skillsFor(s);
  final days = daysLeft(s);
  final brief = s['brief'] as Json?;
  final b = StringBuffer()
    ..writeln('# ${s['role']}${company.isEmpty ? '' : ' at $company'}')
    ..writeln()
    ..writeln('Prepared by HireFly. Open the app to work through it; this file is a summary.')
    ..writeln()
    ..writeln('- Questions in the plan: ${active.length} (${intensityNames[(s['intensity'] as int).clamp(1, 5)]} pace)')
    ..writeln('- Tailored to the posting: ${active.where((d) => d.data['source'] == 'tailored').length}${brief == null ? ' (the brief has not been built yet; it needs a Claude API key in HireFly)' : ''}')
    ..writeln('- Interview date: ${s['interviewDate'] ?? 'not set'}${days == null ? '' : ' ($days days away)'}')
    ..writeln();
  if (skills.isNotEmpty) {
    b.writeln('## Skills this role calls for');
    b.writeln();
    for (final (id, why) in skills) {
      final m = content.modules.where((m) => m.id == id).firstOrNull;
      if (m == null) continue;
      b.writeln('### ${m.title}');
      b.writeln('The posting mentions: ${why.join(', ')}. HireFly has ${m.lessons.length} lessons and ${m.labs.length} labs for it.');
      final plan = planFor(m, days);
      if (plan != null) {
        b.writeln();
        b.writeln('Plan for "${plan['when']}" (about ${plan['hours']} hours):');
        for (final step in plan['steps'] as List) {
          b.writeln('1. $step');
        }
      }
      b.writeln();
    }
  }
  if (brief != null) {
    b
      ..writeln('## The role')
      ..writeln()
      ..writeln('${brief['summary']}')
      ..writeln()
      ..writeln('### What they are screening for');
    for (final x in brief['whatTheyWant'] as List) {
      b.writeln('- $x');
    }
    b.writeln('\n### Your edge');
    for (final x in brief['yourEdge'] as List) {
      b.writeln('- ${x['point']}: ${x['evidence']}');
    }
    b.writeln('\n### Where you will be pressed');
    for (final x in brief['gaps'] as List) {
      b.writeln('- ${x['gap']}: ${x['howToAnswer']}');
    }
    b.writeln('\n### Questions to ask them');
    for (final x in brief['questionsToAsk'] as List) {
      b.writeln('- $x');
    }
    b.writeln();
  }
  b.writeln('## Questions');
  b.writeln();
  for (final d in active) {
    b.writeln('- ${d.data['prompt']}${d.data['source'] == 'tailored' ? ' (tailored)' : d.data['source'] == 'skill' ? ' (skill)' : ''}');
  }
  return b.toString();
}

/// A role made from the inbox, or why a file was set aside.
class InboxEvent {
  const InboxEvent({this.sessionId, required this.message});
  final String? sessionId;
  final String message;
}

class Inbox {
  Inbox(this._ref, this.home);
  final Ref _ref;
  final Directory home;
  final _events = StreamController<InboxEvent>.broadcast();
  bool _busy = false;

  Directory get inbox => Directory(p.join(home.path, 'inbox'));
  Directory get outbox => Directory(p.join(home.path, 'outbox'));
  Stream<InboxEvent> get events => _events.stream;

  final _written = <String, DateTime>{};

  /// Writes the role's summary (`.md`) and its work file (`.json`: every
  /// question with the learner's current answer, for a coach outside the app).
  Future<File> writeSummary(Doc session) async {
    final store = _ref.read(storeProvider);
    final s = session.data;
    await outbox.create(recursive: true);
    final name = slug('${s['company']}-${s['role']}');
    final base = p.join(outbox.path, name.isEmpty ? session.id : name);
    final items = await store.list('item', parent: session.id);
    final f = File('$base.md');
    await f.writeAsString(roleSummary(_ref.read(contentProvider), session, items));
    final active = items.where((d) => isActive(d.data)).toList()..sort((a, b) => (a.data['order'] as int).compareTo(b.data['order'] as int));
    await File('$base.json').writeAsString(const JsonEncoder.withIndent(' ').convert({
      'sessionId': session.id,
      'role': s['role'],
      'company': s['company'],
      'hasBrief': s['brief'] != null,
      'items': [
        for (final d in active)
          {'id': d.id, 'prompt': d.data['prompt'], 'category': d.data['category'], 'intent': d.data['intent'], 'guide': d.data['guide'], 'state': d.data['state'], 'answer': d.data['draft'], 'coached': d.data['coach'] != null},
      ],
    }));
    _written[session.id] = _stamp(session, items);
    return f;
  }

  DateTime _stamp(Doc session, List<Doc> items) => items.fold(session.updatedAt, (m, d) => d.updatedAt.isAfter(m) ? d.updatedAt : m);

  /// Rewrites the outbox files of roles whose answers changed since last time.
  Future<void> _refresh() async {
    final store = _ref.read(storeProvider);
    for (final s in await store.list('session')) {
      if (s.data['status'] == 'paused') continue;
      final items = await store.list('item', parent: s.id);
      if (_written[s.id] != _stamp(s, items)) await writeSummary(s);
    }
  }

  /// Handles every request waiting in the inbox. Safe to call often.
  Future<void> poll() async {
    if (_busy) return;
    _busy = true;
    try {
      await inbox.create(recursive: true);
      final files = inbox.listSync().whereType<File>().where((f) => f.path.toLowerCase().endsWith('.json')).toList()..sort((a, b) => a.path.compareTo(b.path));
      for (final f in files) {
        await _handle(f);
      }
      await _refresh();
    } on FileSystemException {
      // The folder is unavailable right now; the next poll tries again.
    } finally {
      _busy = false;
    }
  }

  Future<void> _handle(File file) async {
    final store = _ref.read(storeProvider);
    final sessions = _ref.read(sessionsProvider);
    final String id;
    InboxRole? req;
    try {
      // A coach's results for answers already in the app.
      final raw = jsonDecode(await file.readAsString());
      if (raw is Json && raw['type'] == 'coach') {
        var n = 0;
        for (final r in (raw['results'] as List? ?? const []).whereType<Map>()) {
          if (r['eval'] is Json && await sessions.applyCoach('${r['id']}', r['eval'] as Json)) n++;
        }
        if (n == 0) throw const FormatException('No result matched a question. Each needs the "id" from the role\'s .json file in the outbox and an "eval" with a numeric "score".');
        await shelve(file, 'done');
        _events.add(InboxEvent(message: 'Coaching arrived for $n answer${n == 1 ? '' : 's'}. It is on the Prepare tab.'));
        return;
      }
      req = await readInboxFile(file);
      var fields = req.fields;
      if (req.url != null) {
        final got = await fetchPosting(req.url!);
        fields = {...fields, 'posting': got.text, if ('${fields['company']}'.isEmpty && got.company != null) 'company': got.company};
      }
      id = await sessions.create(fields);
      await sessions.applyBrief(id, req.brief, req.tailored);
      await shelve(file, 'done');
    } on Object catch (e) {
      final why = e is FormatException ? e.message : '$e';
      try {
        await shelve(file, 'failed', note: why);
      } on FileSystemException {
        // Still being written by the other tool; the next poll reads it.
        return;
      }
      _events.add(InboxEvent(message: 'A role request in the inbox couldn\'t be used: $why'));
      return;
    }
    var doc = (await store.get(id))!;
    await writeSummary(doc);
    _events.add(InboxEvent(sessionId: id, message: 'New role from your inbox: ${doc.data['role']}${'${doc.data['company']}'.isEmpty ? '' : ' at ${doc.data['company']}'}'));
    // With a key, the brief and tailored questions follow, and the summary is rewritten.
    if (doc.data['brief'] == null && (await _ref.read(aiClientProvider).settings()).hasKey && '${doc.data['posting']}'.trim().isNotEmpty) {
      try {
        await sessions.buildBrief(doc);
        doc = (await store.get(id))!;
        await writeSummary(doc);
      } on AiFailure {
        // The role is usable without its brief; Overview offers to build it.
      }
    }
  }
}

final inboxProvider = Provider<Inbox>((ref) {
  final inbox = Inbox(ref, ref.watch(hireflyHomeProvider));
  final timer = Timer.periodic(const Duration(seconds: 4), (_) => inbox.poll());
  ref.onDispose(timer.cancel);
  return inbox;
});
