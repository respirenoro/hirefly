import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../data/db.dart';
import '../engine/engine.dart';
import '../engine/intake.dart';
import '../engine/sessions.dart';
import 'shell.dart';
import 'ui.dart';

/// Sets up a role, or edits one: the posting, the resume that was sent, what
/// is known about the company and the interviewer, the date, and the pace.
class NewSessionScreen extends ConsumerStatefulWidget {
  const NewSessionScreen({super.key, this.editId});

  /// The role being edited; null creates one.
  final String? editId;

  @override
  ConsumerState<NewSessionScreen> createState() => _NewSessionScreenState();
}

class _NewSessionScreenState extends ConsumerState<NewSessionScreen> {
  final _company = TextEditingController(), _role = TextEditingController(), _posting = TextEditingController();
  final _resume = TextEditingController(), _target = TextEditingController(), _interviewer = TextEditingController();
  final _research = TextEditingController();
  final _url = TextEditingController();
  bool _fetching = false;
  bool _useTarget = false, _busy = false;
  int _intensity = 3;
  DateTime? _date;

  static const _dirKey = 'resumeDir';

  @override
  void initState() {
    super.initState();
    final id = widget.editId;
    if (id != null) {
      ref.read(storeProvider).get(id).then((d) {
        if (d == null || !mounted) return;
        final s = d.data;
        setState(() {
          _company.text = '${s['company'] ?? ''}';
          _role.text = '${s['role'] ?? ''}';
          _posting.text = '${s['posting'] ?? ''}';
          _resume.text = '${s['resume'] ?? ''}';
          _target.text = '${s['targetResume'] ?? ''}';
          _interviewer.text = '${s['interviewer'] ?? ''}';
          _research.text = '${s['research'] ?? ''}';
          _url.text = '${s['postingUrl'] ?? ''}';
          _useTarget = s['useTarget'] == true;
          _intensity = (s['intensity'] as int).clamp(1, 5);
          _date = DateTime.tryParse('${s['interviewDate'] ?? ''}');
        });
      });
    }
  }

  @override
  void dispose() {
    for (final c in [_company, _role, _posting, _resume, _target, _interviewer, _research, _url]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Opens in the folder a resume was last picked from.
  Future<void> _pick(TextEditingController into) async {
    final store = ref.read(storeProvider);
    final last = await store.setting(_dirKey);
    final file = await openFile(
      initialDirectory: last != null && Directory(last).existsSync() ? last : null,
      acceptedTypeGroups: const [XTypeGroup(label: 'Resume', extensions: ['html', 'htm', 'md', 'txt'])],
    );
    if (file == null) return;
    await store.setSetting(_dirKey, p.dirname(file.path));
    try {
      into.text = await readResumeFile(file.path);
      if (_company.text.trim().isEmpty) {
        // Tailored resumes are often named "Company (Role) - Resume.html".
        final m = RegExp(r'^(.*?)(?:\s*\((.*)\))?\s*-\s*Resume').firstMatch(p.basenameWithoutExtension(file.path));
        if (m != null) {
          _company.text = m.group(1)!.trim();
          if (_role.text.trim().isEmpty && m.group(2) != null) _role.text = m.group(2)!.trim();
        }
      }
      setState(() {});
    } on FileSystemException {
      if (mounted) say(context, 'That file couldn\'t be read as text. Paste the resume instead.');
    }
  }

  Future<void> _fetch() async {
    if (_url.text.trim().isEmpty) return say(context, 'Paste the posting\'s web address first.');
    setState(() => _fetching = true);
    try {
      final got = await fetchPosting(_url.text);
      if (!mounted) return;
      setState(() {
        _posting.text = got.text;
        if (_role.text.trim().isEmpty && got.title != null) _role.text = got.title!;
        if (_company.text.trim().isEmpty && got.company != null) _company.text = got.company!;
      });
      say(context, 'Posting loaded. Check the title and company, then build the plan.');
    } on IntakeFailure catch (e) {
      if (mounted) say(context, e.message);
    } finally {
      if (mounted) setState(() => _fetching = false);
    }
  }

  Future<void> _save() async {
    if (_role.text.trim().isEmpty) return say(context, 'Give the role a title, such as "QA Analyst".');
    setState(() => _busy = true);
    final d = _date;
    final fields = {
      'company': _company.text.trim(),
      'role': _role.text.trim(),
      'posting': _posting.text.trim(),
      'resume': _resume.text.trim(),
      'targetResume': _target.text.trim(),
      'useTarget': _useTarget && _target.text.trim().isNotEmpty,
      'interviewer': _interviewer.text.trim(),
      'research': _research.text.trim(),
      'postingUrl': _url.text.trim().isEmpty ? null : _url.text.trim(),
      'interviewDate': d == null ? null : '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
    };
    final sessions = ref.read(sessionsProvider);
    final store = ref.read(storeProvider);
    final String id;
    if (widget.editId == null) {
      id = await sessions.create({...fields, 'intensity': _intensity});
    } else {
      id = widget.editId!;
      await store.patch(id, fields);
      final doc = await store.get(id);
      if (doc != null && doc.data['intensity'] != _intensity) await sessions.setIntensity(doc, _intensity);
    }
    if (mounted) ref.go('role', id, widget.editId == null ? 'new' : null);
  }

  Widget _resumeField(String label, TextEditingController c, String hint) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Expanded(child: Label(label)), JBtn('Choose a file', icon: 'folder', quiet: true, onTap: () => _pick(c))]),
        TextField(controller: c, minLines: 3, maxLines: 8, decoration: writeField(hint)),
      ]);

  @override
  Widget build(BuildContext context) {
    final pal = context.palette;
    final t = Theme.of(context).textTheme;
    final edit = widget.editId != null;
    final d = _date;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      PageTop(
        title: edit ? 'Role details' : 'New role',
        onBack: edit ? () => ref.go('role', widget.editId) : null,
        backLabel: 'Back to the role',
        actions: [BusyButton(busy: _busy, filled: true, icon: 'check', onPressed: _save, label: edit ? 'Save' : 'Build the plan')],
      ),
      Expanded(
        child: Sheet(width: 760, children: [
          Row(children: [
            Expanded(child: TextField(key: const Key('role-title'), controller: _role, decoration: const InputDecoration(labelText: 'Role title'))),
            const SizedBox(width: 12),
            Expanded(child: TextField(key: const Key('role-company'), controller: _company, decoration: const InputDecoration(labelText: 'Company (empty for general practice)'))),
          ]),
          const SizedBox(height: 18),
          const Label('Interview date'),
          Row(children: [
            JBtn(
              d == null ? 'Set a date' : '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
              icon: 'cal',
              onTap: () async {
                final now = DateTime.now();
                final picked = await showDatePicker(context: context, initialDate: d ?? now, firstDate: now.subtract(const Duration(days: 30)), lastDate: now.add(const Duration(days: 365)));
                if (picked != null) setState(() => _date = picked);
              },
            ),
            if (d != null) ...[const SizedBox(width: 8), JBtn('Clear', quiet: true, onTap: () => setState(() => _date = null))],
            const SizedBox(width: 12),
            Expanded(child: Text('With a date, Today shows a countdown and spreads the remaining work across the days left.', style: t.bodySmall)),
          ]),
          const SizedBox(height: 18),
          const Label('Job posting'),
          Row(children: [
            Expanded(child: TextField(key: const Key('posting-url'), controller: _url, onSubmitted: (_) => _fetch(), decoration: const InputDecoration(hintText: 'Paste the posting\'s web address to load it, or paste its text below'))),
            const SizedBox(width: 8),
            BusyButton(busy: _fetching, icon: 'download', onPressed: _fetch, label: 'Load from the address'),
          ]),
          const SizedBox(height: 8),
          TextField(controller: _posting, minLines: 4, maxLines: 12, decoration: writeField('Paste the full posting. The plan, the brief and the interviewer are built from it.')),
          const SizedBox(height: 18),
          _resumeField('Resume you sent for this role', _resume, 'Choose the tailored resume file (.html, .md, .txt) or paste its text.'),
          const SizedBox(height: 18),
          _resumeField('Target-state resume (optional)', _target, 'The version that includes skills you are still building.'),
          const SizedBox(height: 8),
          Row(children: [
            JChk(_useTarget, label: 'Prepare me against the target-state resume', onChanged: (v) => setState(() => _useTarget = v)),
            Expanded(child: Text('Prepare me against the target-state resume: the coach and interviewer hold you to every line of it, with honest wording for skills still in progress.', style: t.bodyMedium?.copyWith(color: pal.textMuted))),
          ]),
          const SizedBox(height: 18),
          const Label('Company research (optional)'),
          TextField(controller: _research, minLines: 3, maxLines: 10, decoration: writeField('Paste the company\'s About page, product pages, recent news or reviews. It feeds "why this company", your questions for them, and scenario questions set in their work.')),
          const SizedBox(height: 18),
          const Label('Who is interviewing you (optional)'),
          TextField(controller: _interviewer, minLines: 2, maxLines: 8, decoration: writeField('Name, title, and anything from their LinkedIn profile or the recruiter\'s email. The mock interviewer takes on their priorities and manner.')),
          const SizedBox(height: 18),
          const Label('How thorough'),
          Row(children: [
            JSeg<int>(items: [for (var i = 1; i <= 5; i++) JSegItem(i, intensityNames[i])], value: _intensity, onChanged: (v) => setState(() => _intensity = v)),
            const SizedBox(width: 12),
            Text('about ${planSize(_intensity)} questions', style: t.bodyMedium?.copyWith(color: pal.textMuted)),
          ]),
          const SizedBox(height: 6),
          Text('You can change this at any time inside the role, and HireFly trims the plan by itself where you are already strong.', style: t.bodySmall),
        ]),
      ),
    ]);
  }
}
