import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/export.dart';
import '../engine/sandbox.dart';
import 'shell.dart';
import 'ui.dart';

/// The scratch databases: `practice` (the full practice data) and `sample`
/// (the eight-shift tables the SQL lessons reason about).
final sandboxProvider = FutureProvider.family<Sandbox, String>((ref, name) async {
  final script = await rootBundle.loadString('assets/content/datasets/${name == 'sample' ? 'lesson_sample' : 'practice'}.sql');
  final box = Sandbox(script);
  ref.onDispose(box.dispose);
  return box;
});

/// A query's rows as a plain grid; text selects with the page.
class ResultTable extends StatelessWidget {
  const ResultTable(this.result, {super.key});
  final QueryResult result;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final r = result;
    if (r.error != null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: p.danger.withValues(alpha: .1), borderRadius: BorderRadius.circular(p.radius)),
        child: Text(r.error!, style: context.mono.copyWith(color: p.danger, fontSize: 13)),
      );
    }
    if (r.columns.isEmpty) return Text('Done. ${r.changed ?? 0} row${r.changed == 1 ? '' : 's'} changed.', style: t.bodyMedium?.copyWith(color: p.textMuted));
    final cell = context.mono.copyWith(fontSize: 12.5, letterSpacing: 0);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('${r.rows.length} row${r.rows.length == 1 ? '' : 's'}${r.truncated ? ' shown; there are more' : ''}', style: t.bodySmall),
      const SizedBox(height: 6),
      Container(
        constraints: const BoxConstraints(maxHeight: 340),
        decoration: BoxDecoration(border: Border.all(color: p.lineStrong), borderRadius: BorderRadius.circular(p.radius)),
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Table(
              defaultColumnWidth: const IntrinsicColumnWidth(),
              border: TableBorder(horizontalInside: BorderSide(color: p.border), verticalInside: BorderSide(color: p.border)),
              children: [
                TableRow(decoration: BoxDecoration(color: p.s3), children: [for (final c in r.columns) Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), child: Text(c, style: cell.weight(500)))]),
                for (final row in r.rows)
                  TableRow(children: [
                    for (final v in row)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        child: Text(v == null ? 'NULL' : '$v', style: cell.copyWith(color: v == null ? p.textFaint : p.text)),
                      ),
                  ]),
              ],
            ),
          ),
        ),
      ),
    ]);
  }
}

/// An editor that runs SQL against a sandbox. Ctrl+Enter runs.
class SqlRunner extends ConsumerStatefulWidget {
  const SqlRunner({super.key, required this.database, this.initial = '', this.onRun, this.lines = 6, this.extra = const []});
  final String database, initial;
  final int lines;

  /// Told each query that was run and its result.
  final void Function(String sql, QueryResult result)? onRun;

  /// Buttons after Run.
  final List<Widget> extra;

  @override
  ConsumerState<SqlRunner> createState() => SqlRunnerState();
}

class SqlRunnerState extends ConsumerState<SqlRunner> {
  late final _sql = TextEditingController(text: widget.initial);
  QueryResult? _result;

  String get text => _sql.text;

  @override
  void dispose() {
    _sql.dispose();
    super.dispose();
  }

  Future<QueryResult?> run() async {
    final box = await ref.read(sandboxProvider(widget.database).future);
    final r = box.run(_sql.text);
    if (!mounted) return r;
    setState(() => _result = r);
    widget.onRun?.call(_sql.text, r);
    return r;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.enter, control: true): run},
        child: TextField(
          key: const Key('sql-editor'),
          controller: _sql,
          minLines: widget.lines,
          maxLines: 22,
          style: TextStyle(fontFamily: context.fonts.numbers, fontSize: 13.5, height: 1.5, color: p.text),
          decoration: writeField('SELECT ... FROM shifts'),
        ),
      ),
      const SizedBox(height: 8),
      Row(children: [
        JBtn('Run', icon: 'play', primary: true, onTap: run),
        const SizedBox(width: 8),
        const JKbd('Ctrl'),
        const SizedBox(width: 3),
        const JKbd('Enter'),
        const SizedBox(width: 12),
        for (final e in widget.extra) Padding(padding: const EdgeInsets.only(right: 8), child: e),
      ]),
      if (_result != null) ...[const SizedBox(height: 12), ResultTable(_result!)],
    ]);
  }
}

/// A free SQL workspace on the practice data.
class SandboxScreen extends ConsumerStatefulWidget {
  const SandboxScreen({super.key});

  @override
  ConsumerState<SandboxScreen> createState() => _SandboxScreenState();
}

class _SandboxScreenState extends ConsumerState<SandboxScreen> {
  String _db = 'practice';

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final box = ref.watch(sandboxProvider(_db));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      PageTop(
        title: 'SQL sandbox',
        onBack: () => ref.go('skill', 'sql'),
        backLabel: 'SQL',
        actions: [
          JSeg<String>(items: const [JSegItem('practice', 'Practice data'), JSegItem('sample', 'Lesson sample')], value: _db, onChanged: (v) => setState(() => _db = v)),
          JBtn('Reset data', icon: 'refresh', onTap: () {
            box.value?.reset();
            say(context, 'The tables are back to how they started.');
          }),
          JBtn('Export the data', icon: 'download', onTap: () async {
            await showInExplorer(await exportPracticeData());
          }),
        ],
      ),
      Expanded(
        child: box.when(
          loading: () => const SizedBox.shrink(),
          error: (e, _) => Center(child: Text(_db == 'sample' ? 'The lesson sample is not in this build yet.' : 'The practice data could not be loaded.', style: t.bodyMedium?.copyWith(color: p.textMuted))),
          data: (b) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Sheet(width: 900, children: [
                Text('This runs SQLite in memory, so nothing you do here can break anything. SQLite differs from SQL Server in a few places: LIMIT instead of TOP, julianday() and strftime() instead of DATEDIFF and DATEPART, and || to join text.', style: t.bodyMedium?.copyWith(color: p.textMuted)),
                const SizedBox(height: 12),
                SqlRunner(key: ValueKey(_db), database: _db, lines: 9, initial: 'SELECT status, COUNT(*) AS shifts\nFROM shifts\nGROUP BY status\nORDER BY shifts DESC;'),
              ]),
            ),
            Container(
              width: 250,
              decoration: BoxDecoration(border: Border(left: BorderSide(color: p.border))),
              child: SelectionArea(
                child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
                  const Label('Tables'),
                  for (final e in b.schema.entries) ...[
                    Padding(padding: const EdgeInsets.only(top: 8, bottom: 2), child: Text(e.key, style: context.mono.copyWith(color: p.ink))),
                    for (final c in e.value) Text('  $c', style: context.mono.copyWith(color: p.textMuted)),
                  ],
                ]),
              ),
            ),
          ]),
        ),
      ),
    ]);
  }
}
