import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

part 'db.g.dart';

const _uuid = Uuid();

/// Time-ordered UUID v7 (from Soloza's `core/ids.dart`).
String newId() => _uuid.v7();

DateTime nowUtc() => DateTime.now().toUtc();

/// Everything the learner creates is one JSON document: a prep session, a
/// question in it, an attempt, a mock run, lesson progress. [kind] names the
/// type and [parent] the document it belongs to.
@DataClassName('DocRow')
class Docs extends Table {
  TextColumn get id => text()();
  TextColumn get kind => text()();
  TextColumn get parent => text().nullable()();
  TextColumn get json => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

/// One row per assistant call, for the monthly cap (from Soloza's `ai_tables.dart`).
class AiCalls extends Table {
  TextColumn get id => text()();
  DateTimeColumn get createdAt => dateTime()();
  TextColumn get model => text()();
  TextColumn get task => text()();
  IntColumn get latencyMs => integer().withDefault(const Constant(0))();
  IntColumn get inTok => integer().withDefault(const Constant(0))();
  IntColumn get outTok => integer().withDefault(const Constant(0))();
  IntColumn get cacheReadTok => integer().withDefault(const Constant(0))();
  IntColumn get costMicros => integer().withDefault(const Constant(0))();
  TextColumn get status => text()();
  TextColumn get errorCode => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [Docs, Settings, AiCalls])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? e]) : super(e ?? driftDatabase(name: 'hirefly'));

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await customStatement('CREATE INDEX docs_kind_parent ON docs (kind, parent)');
        },
      );
}

typedef Json = Map<String, dynamic>;

/// A stored document with its decoded body.
class Doc {
  Doc(this.id, this.kind, this.parent, this.data, this.createdAt, this.updatedAt);
  final String id, kind;
  final String? parent;
  final Json data;
  final DateTime createdAt, updatedAt;

  static Doc of(DocRow r) => Doc(r.id, r.kind, r.parent, jsonDecode(r.json) as Json, r.createdAt, r.updatedAt);
}

class Store {
  Store(this.db);
  final AppDatabase db;

  Stream<List<Doc>> watch(String kind, {String? parent}) {
    final q = db.select(db.docs)..where((t) => t.kind.equals(kind));
    if (parent != null) q.where((t) => t.parent.equals(parent));
    q.orderBy([(t) => OrderingTerm.asc(t.id)]);
    return q.watch().map((rows) => rows.map(Doc.of).toList());
  }

  Future<List<Doc>> list(String kind, {String? parent}) => watch(kind, parent: parent).first;

  Stream<Doc?> watchOne(String id) =>
      (db.select(db.docs)..where((t) => t.id.equals(id))).watchSingleOrNull().map((r) => r == null ? null : Doc.of(r));

  Future<Doc?> get(String id) async {
    final r = await (db.select(db.docs)..where((t) => t.id.equals(id))).getSingleOrNull();
    return r == null ? null : Doc.of(r);
  }

  /// Inserts or replaces. Returns the id.
  Future<String> put(String kind, Json data, {String? id, String? parent}) async {
    final docId = id ?? newId();
    final now = nowUtc();
    final old = await (db.select(db.docs)..where((t) => t.id.equals(docId))).getSingleOrNull();
    await db.into(db.docs).insertOnConflictUpdate(DocsCompanion.insert(
          id: docId,
          kind: kind,
          parent: Value(parent ?? old?.parent),
          json: jsonEncode(data),
          createdAt: old?.createdAt ?? now,
          updatedAt: now,
        ));
    return docId;
  }

  /// Merges [changes] into an existing document.
  Future<void> patch(String id, Json changes) async {
    final d = await get(id);
    if (d == null) return;
    await put(d.kind, {...d.data, ...changes}, id: id, parent: d.parent);
  }

  Future<void> delete(String id) => (db.delete(db.docs)..where((t) => t.id.equals(id))).go();

  /// Deletes a document and everything under it, two levels deep (a session,
  /// its questions and mocks, and their attempts).
  Future<void> deleteTree(String id) => db.transaction(() async {
        final kids = await (db.select(db.docs)..where((t) => t.parent.equals(id))).get();
        for (final k in kids) {
          await (db.delete(db.docs)..where((t) => t.parent.equals(k.id))).go();
        }
        await (db.delete(db.docs)..where((t) => t.parent.equals(id))).go();
        await delete(id);
      });

  Future<String?> setting(String key) async =>
      (await (db.select(db.settings)..where((t) => t.key.equals(key))).getSingleOrNull())?.value;

  Stream<String?> watchSetting(String key) =>
      (db.select(db.settings)..where((t) => t.key.equals(key))).watchSingleOrNull().map((r) => r?.value);

  Future<void> setSetting(String key, String value) =>
      db.into(db.settings).insertOnConflictUpdate(SettingsCompanion.insert(key: key, value: value));
}

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final storeProvider = Provider<Store>((ref) => Store(ref.watch(databaseProvider)));

/// Documents of one kind, optionally under one parent: `(kind, parent)`.
final docsProvider = StreamProvider.autoDispose.family<List<Doc>, (String, String?)>(
    (ref, k) => ref.watch(storeProvider).watch(k.$1, parent: k.$2));

final docProvider = StreamProvider.autoDispose.family<Doc?, String>((ref, id) => ref.watch(storeProvider).watchOne(id));
