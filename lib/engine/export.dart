// Files HireFly writes for use outside the app: a role's cheat sheet, and the
// practice data for Excel, Power BI and SQL tools. Both go under
// Documents\HireFly.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/db.dart';
import 'engine.dart';

const datasetFiles = ['practice.sql', 'lesson_sample.sql', 'shifts.csv', 'pharmacies.csv', 'pharmacists.csv', 'assignments.csv', 'tickets.csv'];

Future<Directory> _home(String sub) async {
  final docs = await getApplicationDocumentsDirectory();
  return Directory(p.join(docs.path, 'HireFly', sub)).create(recursive: true);
}

/// Copies the bundled practice data to Documents\HireFly\practice-data and
/// returns one of the files, to show in Explorer.
Future<File> exportPracticeData() async {
  final dir = await _home('practice-data');
  File? first;
  for (final name in datasetFiles) {
    try {
      final data = await rootBundle.load('assets/content/datasets/$name');
      final f = File(p.join(dir.path, name));
      await f.writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
      first ??= f;
    } on Exception {
      // A file not in this build is skipped.
    }
  }
  return first ?? File(p.join(dir.path, datasetFiles.first));
}

String _e(Object? s) => const HtmlEscape().convert('${s ?? ''}');
String _para(Object? s) => _e(s).replaceAll('\n', '<br>');
String _list(Iterable<Object?> items) => '<ul>${items.map((i) => '<li>${_e(i)}</li>').join()}</ul>';

/// The one-file summary to read before the interview: the brief, the ready
/// answers and the questions to ask. Returns the file.
Future<File> exportCheatSheet(Doc session, List<Doc> items) async {
  final s = session.data;
  final brief = s['brief'] as Json?;
  final company = '${s['company']}'.trim();
  final title = '${company.isEmpty ? 'General' : company} - ${s['role']} - Cheat Sheet';
  final ready = items.where((d) => isActive(d.data) && '${d.data['draft']}'.trim().isNotEmpty).toList()
    ..sort((a, b) => (a.data['order'] as int).compareTo(b.data['order'] as int));
  final b = StringBuffer()
    ..write('<!doctype html><html lang="en"><head><meta charset="utf-8"><title>${_e(title)}</title><style>'
        'body{font:15px/1.55 Georgia,serif;max-width:780px;margin:32px auto;padding:0 24px;color:#1b1a18}'
        'h1{font-size:26px;margin-bottom:2px}h2{font-size:18px;margin-top:28px;border-bottom:1px solid #ccc;padding-bottom:4px}'
        'h3{font:600 15px/1.4 Segoe UI,sans-serif;margin:18px 0 4px}.m{color:#666;font:13px Segoe UI,sans-serif}'
        'li{margin-bottom:4px}@media print{h2{break-after:avoid}h3{break-after:avoid}}</style></head><body>')
    ..write('<h1>${_e(s['role'])}</h1><div class="m">${_e(company)}${s['interviewDate'] == null ? '' : ' · interview ${_e(s['interviewDate'])}'}</div>');
  if (brief != null) {
    b
      ..write('<h2>The role</h2><p>${_para(brief['summary'])}</p>')
      ..write('<h3>What they are screening for</h3>${_list(brief['whatTheyWant'] as List)}')
      ..write('<h3>Your edge</h3>${_list([for (final e in brief['yourEdge'] as List) '${e['point']}: ${e['evidence']}'])}')
      ..write('<h3>Where you will be pressed</h3>${_list([for (final e in brief['gaps'] as List) '${e['gap']}: ${e['howToAnswer']}'])}')
      ..write('<h3>Why this company</h3><p>${_para(brief['whyThisCompany'])}</p>')
      ..write('<h3>Questions to ask</h3>${_list(brief['questionsToAsk'] as List)}');
  }
  if ('${s['research'] ?? ''}'.trim().isNotEmpty) b.write('<h2>Your research notes</h2><p>${_para(s['research'])}</p>');
  b.write('<h2>Your answers (${ready.length})</h2>');
  for (final d in ready) {
    b.write('<h3>${_e(d.data['prompt'])}</h3><p>${_para(d.data['draft'])}</p>');
  }
  if (ready.isEmpty) b.write('<p class="m">No answers written yet.</p>');
  b.write('</body></html>');
  final dir = await _home('cheat-sheets');
  final safe = title.replaceAll(RegExp(r'[\\/:*?"<>|]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  final f = File(p.join(dir.path, '$safe.html'));
  await f.writeAsString(b.toString());
  return f;
}
