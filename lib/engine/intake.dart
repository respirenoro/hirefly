// Getting a role into HireFly without typing it: from a job posting's URL,
// or from a file another tool (a Claude Code session, a script) drops in the
// inbox folder. Also which skill modules a role calls for.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../data/content.dart';
import '../data/db.dart';

/// Readable text of an HTML fragment or page: one line per block.
String htmlToText(String source) {
  final doc = html.parse(source);
  doc.querySelectorAll('style,script,noscript,svg,nav,footer,header,form').forEach((e) => e.remove());
  for (final e in doc.querySelectorAll('p,div,li,h1,h2,h3,h4,h5,tr,br,section,ul,ol')) {
    e.append(dom.Text('\n'));
  }
  for (final e in doc.querySelectorAll('li')) {
    e.nodes.insert(0, dom.Text('- '));
  }
  return (doc.body?.text ?? doc.documentElement?.text ?? '')
      .split('\n')
      .map((l) => l.replaceAll(RegExp(r'[ \t\u00a0]+'), ' ').trim())
      .where((l) => l.isNotEmpty && l != '-')
      .join('\n');
}

/// A posting read from a web page.
class FetchedPosting {
  const FetchedPosting({required this.text, this.title, this.company});
  final String text;
  final String? title, company;
}

/// Thrown with words for the learner when a page can't be used.
class IntakeFailure implements Exception {
  const IntakeFailure(this.message);
  final String message;

  @override
  String toString() => message;
}

Iterable<Map<String, dynamic>> _jsonLd(Object? node) sync* {
  if (node is List) {
    for (final n in node) {
      yield* _jsonLd(n);
    }
  } else if (node is Map<String, dynamic>) {
    yield node;
    yield* _jsonLd(node['@graph']);
  }
}

/// Reads a job posting out of a page's HTML. Job boards publish the posting
/// as structured data (schema.org `JobPosting`) for search engines; that is
/// used when present, since it is the posting and nothing else. Otherwise the
/// page's main text is taken.
FetchedPosting parsePosting(String page) {
  final doc = html.parse(page);
  for (final s in doc.querySelectorAll('script[type="application/ld+json"]')) {
    try {
      for (final j in _jsonLd(jsonDecode(s.text))) {
        final type = j['@type'];
        if (type == 'JobPosting' || (type is List && type.contains('JobPosting'))) {
          final org = j['hiringOrganization'];
          final where = j['jobLocation'];
          final place = where is Map ? where['address'] : (where is List && where.isNotEmpty && where.first is Map ? (where.first as Map)['address'] : null);
          final text = [
            if (j['employmentType'] != null) 'Employment type: ${j['employmentType'] is List ? (j['employmentType'] as List).join(', ') : j['employmentType']}',
            if (j['jobLocationType'] != null) 'Location type: ${j['jobLocationType']}',
            if (place is Map) 'Location: ${[place['addressLocality'], place['addressRegion'], place['addressCountry'] is Map ? (place['addressCountry'] as Map)['name'] : place['addressCountry']].where((x) => x != null).join(', ')}',
            htmlToText('${j['description'] ?? ''}'),
            for (final k in ['responsibilities', 'qualifications', 'skills', 'experienceRequirements', 'educationRequirements'])
              if (j[k] is String && (j[k] as String).trim().isNotEmpty) '${k[0].toUpperCase()}${k.substring(1)}:\n${htmlToText(j[k] as String)}',
          ].where((s) => s.trim().isNotEmpty).join('\n\n');
          if (text.length > 200) {
            return FetchedPosting(text: text, title: (j['title'] as String?)?.trim(), company: org is Map ? (org['name'] as String?)?.trim() : null);
          }
        }
      }
    } on FormatException {
      // Not JSON after all; try the next block.
    }
  }
  final main = doc.querySelector('main') ?? doc.querySelector('article') ?? doc.querySelector('[role="main"]');
  final text = htmlToText(main?.outerHtml ?? page);
  final title = doc.querySelector('meta[property="og:title"]')?.attributes['content'] ?? doc.querySelector('title')?.text;
  final site = doc.querySelector('meta[property="og:site_name"]')?.attributes['content'];
  return FetchedPosting(text: text, title: title?.trim(), company: site?.trim());
}

/// Downloads a posting. Throws [IntakeFailure] with a plain reason.
Future<FetchedPosting> fetchPosting(String url, {http.Client? client}) async {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https') || uri.host.isEmpty) {
    throw const IntakeFailure('That is not a web address. It should start with https://');
  }
  final c = client ?? http.Client();
  try {
    final r = await c.get(uri, headers: const {
      'user-agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36',
      'accept': 'text/html,application/xhtml+xml',
      'accept-language': 'en-US,en;q=0.9',
    }).timeout(const Duration(seconds: 25));
    if (r.statusCode == 401 || r.statusCode == 403) throw const IntakeFailure('That site refused the request (it blocks apps or needs a sign-in). Open it in your browser and paste the posting.');
    if (r.statusCode != 200) throw IntakeFailure('The page answered with an error (${r.statusCode}). Paste the posting instead.');
    final posting = parsePosting(utf8.decode(r.bodyBytes, allowMalformed: true));
    if (posting.text.length < 400) {
      throw const IntakeFailure('That page has no readable posting in it; many job boards build the page with scripts. Open it in your browser and paste the posting.');
    }
    return posting;
  } on TimeoutException {
    throw const IntakeFailure('The page took too long to answer. Paste the posting instead.');
  } on SocketException {
    throw const IntakeFailure('Couldn\'t reach that address. Check your connection, or paste the posting.');
  } on http.ClientException {
    throw const IntakeFailure('Couldn\'t reach that address. Check your connection, or paste the posting.');
  } on HandshakeException {
    throw const IntakeFailure('Couldn\'t connect to that site securely. Paste the posting instead.');
  } finally {
    if (client == null) c.close();
  }
}

/// Words in a posting that point to each skill module: first the names of
/// tools and practices that settle it, then general wording that only hints.
const _skillWords = <String, (List<String> names, List<String> hints)>{
  'sql': (['sql', 't-sql', 'postgres', 'mysql', 'snowflake', 'bigquery', 'relational database'], ['queries', 'querying', 'database']),
  'excel': (['excel', 'pivot table', 'vlookup', 'xlookup', 'google sheets', 'spreadsheet'], ['microsoft office', 'ms office', 'microsoft suite', 'microsoft 365']),
  'power-bi': (['power bi', 'powerbi', 'dax', 'tableau', 'looker'], ['dashboard', 'data visualization', 'business intelligence', 'reporting tool']),
  'jira': (['jira', 'atlassian', 'confluence'], ['kanban', 'scrum', 'sprint', 'backlog', 'agile']),
  'azure-devops': (['azure devops', 'azure boards', 'azure pipelines', 'tfs'], ['devops', 'pipelines', 'ci/cd', 'work items']),
  'ado-test-plans': (
    ['test plan', 'test case', 'test management', 'uat', 'user acceptance', 'testrail', 'zephyr', 'manual testing', 'regression test'],
    ['quality assurance', 'qa ', 'testing', 'defect'],
  ),
  'playwright': (['playwright', 'selenium', 'cypress', 'test automation', 'automated test'], ['automation', 'end-to-end', 'e2e', 'test scripts']),
  'ticket-process': (['zendesk', 'servicenow', 'freshdesk', 'ticketing', 'help desk', 'service desk', 'sla'], ['ticket', 'escalat', 'triage', 'incident', 'troubleshoot', 'support']),
  'documentation': (
    ['knowledge base', 'user guide', 'release notes', 'technical writing', 'standard operating procedure', 'sop', 'user stories'],
    ['documentation', 'requirements', 'training materials', 'document'],
  ),
};

int _mentions(String text, String word) => RegExp('(?<![a-z])${RegExp.escape(word.trim())}').allMatches(text).length;

/// The skill modules a role calls for, strongest signal first, with the words
/// that matched. A named tool counts four times a general hint, no word counts
/// more than three times (so one repeated word can't carry a skill), and a
/// single hint alone is not enough. The resume only breaks ties.
List<(String id, List<String> why)> skillsFor(Json session) {
  final text = ' ${session['role'] ?? ''} ${session['posting'] ?? ''} '.toLowerCase();
  final resume = ' ${session['useTarget'] == true ? session['targetResume'] : session['resume']} '.toLowerCase();
  final out = <(String, List<String>, double)>[];
  for (final e in _skillWords.entries) {
    final (names, hints) = e.value;
    final hits = <String>[];
    var score = 0.0;
    for (final (words, weight) in [(names, 4.0), (hints, 1.0)]) {
      for (final w in words) {
        final n = _mentions(text, w);
        if (n > 0) {
          hits.add(w.trim());
          score += weight * (n > 3 ? 3 : n);
        }
      }
    }
    if (score < 2) continue;
    if (names.any((w) => _mentions(resume, w) > 0)) score += .5;
    out.add((e.key, hits, score));
  }
  out.sort((a, b) => b.$3.compareTo(a.$3));
  return [for (final (id, why, _) in out) (id, why)];
}

/// Plan items made from the interview questions of the skills a role needs,
/// [perSkill] from each. Their model answers ride along for the Prepare view.
List<Json> skillItems(Content content, Json session, {required int perSkill, required int startOrder}) {
  var order = startOrder;
  return [
    for (final (id, _) in skillsFor(session).take(6))
      for (final q in content.modules.where((m) => m.id == id).expand((m) => m.interviewQuestions).take(perSkill))
        {
          'order': order++,
          'qid': q['id'],
          'prompt': q['prompt'],
          'category': 'role',
          'competency': 'technical-knowledge',
          'intent': 'Whether you can back up ${content.modules.firstWhere((m) => m.id == id).title} on your resume with specifics, and where your knowledge stops.',
          'framework': 'Claim-Evidence-Tie',
          'guide': const ['Say your honest level in one sentence.', 'Give one concrete thing you did or built with it.', 'Tie it to what this role needs.'],
          'pitfalls': const ['Claiming more than you can demonstrate in a follow-up.'],
          'followUps': const ['Walk me through exactly how you did that.', 'What would you do differently now?'],
          'source': 'skill',
          'skill': id,
          'model': q['strongAnswer'],
          'draft': '',
          'state': 'new',
          'attempts': 0,
        },
  ];
}

/// What a file in the inbox may say. Only `role` is required.
///
/// ```json
/// {"role": "QA Analyst", "company": "Acme Health",
///  "posting": "full text", "url": "https://...", "postingFile": "C:\\...\\posting.md",
///  "resume": "text", "resumeFile": "C:\\...\\Acme - Resume.html",
///  "targetResume": "text", "targetResumeFile": "C:\\...", "useTarget": false,
///  "research": "text", "interviewer": "text",
///  "interviewDate": "2026-11-20", "intensity": 3}
/// ```
class InboxRole {
  InboxRole(this.fields, this.url, {this.brief, this.tailored = const []});

  /// Session fields, ready to save.
  final Json fields;

  /// A posting to download, when no text was given.
  final String? url;

  /// A role brief and tailored questions written by the sender, in the app's
  /// own shapes (see docs/inbox.md).
  final Json? brief;
  final List tailored;
}

Future<String> _textOrFile(Json j, String key) async {
  final direct = '${j[key] ?? ''}'.trim();
  if (direct.isNotEmpty) return direct;
  final path = '${j['${key}File'] ?? ''}'.trim();
  if (path.isEmpty) return '';
  final f = File(path);
  if (!f.existsSync()) throw IntakeFailure('${key}File was not found: $path');
  final raw = await f.readAsString();
  final lower = path.toLowerCase();
  return lower.endsWith('.html') || lower.endsWith('.htm') ? htmlToText(raw) : raw.trim();
}

/// Reads one inbox file. Throws [IntakeFailure] or [FormatException] with the reason.
Future<InboxRole> readInboxFile(File file) async {
  final j = jsonDecode(await file.readAsString());
  if (j is! Json) throw const FormatException('The file must hold one JSON object.');
  final role = '${j['role'] ?? ''}'.trim();
  if (role.isEmpty) throw const FormatException('"role" (the job title) is required.');
  final date = '${j['interviewDate'] ?? ''}'.trim();
  if (date.isNotEmpty && DateTime.tryParse(date) == null) throw const FormatException('"interviewDate" must look like 2026-11-20.');
  final target = await _textOrFile(j, 'targetResume');
  final posting = await _textOrFile(j, 'posting');
  final url = '${j['url'] ?? ''}'.trim();
  return InboxRole({
    'company': '${j['company'] ?? ''}'.trim(),
    'role': role,
    'posting': posting,
    'postingUrl': url.isEmpty ? null : url,
    'resume': await _textOrFile(j, 'resume'),
    'targetResume': target,
    'useTarget': j['useTarget'] == true && target.isNotEmpty,
    'research': await _textOrFile(j, 'research'),
    'interviewer': '${j['interviewer'] ?? ''}'.trim(),
    'interviewDate': date.isEmpty ? null : date.substring(0, 10),
    'intensity': j['intensity'] is num ? (j['intensity'] as num).toInt().clamp(1, 5) : 3,
    'from': 'inbox',
  }, posting.isEmpty && url.isNotEmpty ? url : null, brief: j['brief'] is Json ? j['brief'] as Json : null, tailored: j['tailored'] is List ? j['tailored'] as List : const []);
}

String slug(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');

/// Moves a handled inbox file aside so it is not read twice.
Future<void> shelve(File file, String folder, {String? note}) async {
  final dir = await Directory(p.join(file.parent.path, folder)).create(recursive: true);
  final name = '${DateTime.now().millisecondsSinceEpoch}-${p.basename(file.path)}';
  await file.rename(p.join(dir.path, name));
  if (note != null) await File(p.join(dir.path, '$name.error.txt')).writeAsString(note);
}
