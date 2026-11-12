// A scratch SQL database held in memory, filled from the bundled practice
// data, so queries can be run and checked inside the app.
import 'package:sqlite3/sqlite3.dart';

class QueryResult {
  QueryResult(this.columns, this.rows, {this.error, this.truncated = false, this.changed});
  final List<String> columns;
  final List<List<Object?>> rows;
  final String? error;
  final bool truncated;

  /// Rows changed by a statement that returns none.
  final int? changed;
}

class Sandbox {
  Sandbox(this.script) : _db = sqlite3.openInMemory() {
    _db.execute(script);
  }

  /// The SQL that builds and fills the tables.
  final String script;
  Database _db;

  static const maxRows = 500;

  void reset() {
    _db.close();
    _db = sqlite3.openInMemory()..execute(script);
  }

  void dispose() => _db.close();

  /// Table names with their columns, for the schema panel.
  Map<String, List<String>> get schema => {
        for (final t in _db.select("SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name"))
          t['name'] as String: [for (final c in _db.select('PRAGMA table_info(${t['name']})')) '${c['name']}'],
      };

  /// Runs one statement. A mistake comes back as [QueryResult.error], in
  /// SQLite's own words.
  QueryResult run(String sql, {int limit = maxRows}) {
    final text = sql.trim().replaceAll(RegExp(r';\s*$'), '');
    if (text.isEmpty) return QueryResult(const [], const [], error: 'Write a query first.');
    try {
      final stmt = _db.prepare(text);
      try {
        final cursor = stmt.selectCursor();
        if (cursor.columnNames.isEmpty) {
          // Not a query: stepping it once runs it.
          cursor.moveNext();
          return QueryResult(const [], const [], changed: _db.updatedRows);
        }
        final rows = <List<Object?>>[];
        var more = false;
        while (cursor.moveNext()) {
          if (rows.length >= limit) {
            more = true;
            break;
          }
          rows.add(cursor.current.values);
        }
        return QueryResult(cursor.columnNames, rows, truncated: more);
      } finally {
        stmt.close();
      }
    } on SqliteException catch (e) {
      return QueryResult(const [], const [], error: e.message);
    } on ArgumentError catch (e) {
      return QueryResult(const [], const [], error: '${e.message}');
    }
  }
}

String _cell(Object? v) {
  if (v == null) return 'NULL';
  if (v is num) {
    // 62.5 and 62.50 are the same answer; so are 3 and 3.0.
    final r = (v * 100).roundToDouble() / 100;
    return r == r.roundToDouble() ? r.round().toString() : r.toStringAsFixed(2);
  }
  return '$v'.trim().toLowerCase();
}

/// Whether the learner's result answers the question the model query answers.
/// Column names and column order may differ; values and row count may not.
/// Returns null when it matches, else what is different, in plain words.
String? compareResults(QueryResult mine, QueryResult model, {bool ordered = false}) {
  if (mine.error != null) return mine.error;
  if (mine.columns.length != model.columns.length) {
    return 'Your result has ${mine.columns.length} column${mine.columns.length == 1 ? '' : 's'}; the question asks for ${model.columns.length} (${model.columns.join(', ')}).';
  }
  if (mine.rows.length != model.rows.length) {
    return 'Your result has ${mine.rows.length} row${mine.rows.length == 1 ? '' : 's'}; the expected result has ${model.rows.length}.';
  }
  // A row is compared as its sorted cells, so a different column order still matches.
  String key(List<Object?> r) => (r.map(_cell).toList()..sort()).join('\u0001');
  final a = mine.rows.map(key).toList(), b = model.rows.map(key).toList();
  if (!ordered) {
    a.sort();
    b.sort();
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return ordered ? 'Row ${i + 1} differs from the expected result. Check the values and the ORDER BY.' : 'The right number of rows, but the values differ. Check your filter, join and rounding.';
    }
  }
  return null;
}
