// Adapted from Soloza's `lib/core/ai/ai_client.dart`: one client, plain HTTP,
// a monthly dollar cap, every call logged. Added here: a model choice, a
// cached system prefix, and multi-turn conversations.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../data/db.dart';

class AiSettings {
  const AiSettings({this.claudeKey, this.monthlyCapUsd = 5, this.model = defaultModel});

  final String? claudeKey;
  final double monthlyCapUsd;
  final String model;

  bool get hasKey => claudeKey != null;

  AiSettings copyWith({String? Function()? claudeKey, double? monthlyCapUsd, String? model}) => AiSettings(
        claudeKey: claudeKey == null ? this.claudeKey : claudeKey(),
        monthlyCapUsd: monthlyCapUsd ?? this.monthlyCapUsd,
        model: model ?? this.model,
      );

  Map<String, Object?> toJson() => {'claudeKey': claudeKey, 'monthlyCapUsd': monthlyCapUsd, 'model': model};

  /// Never throws: anything unreadable falls back to the default.
  static AiSettings parse(String? raw) {
    if (raw == null) return const AiSettings();
    try {
      final j = jsonDecode(raw);
      if (j is! Map) return const AiSettings();
      final key = j['claudeKey'];
      return AiSettings(
        claudeKey: key is String && key.trim().isNotEmpty ? key.trim() : null,
        monthlyCapUsd: switch (j['monthlyCapUsd']) { final num n when n >= 0 => n.toDouble(), _ => 5 },
        model: prices.containsKey(j['model']) ? j['model'] as String : defaultModel,
      );
    } on FormatException {
      return const AiSettings();
    }
  }
}

const defaultModel = 'claude-opus-5-5';

/// Dollars per million tokens: (input, output, cache read). A cache write is
/// billed at 1.25x input.
const prices = {
  'claude-opus-5-5': (4.0, 20.0, 0.20),
  'claude-sonnet-5-5': (2.0, 10.0, 0.10),
  'claude-haiku-5-5': (0.10, 0.50, 0.01),
};

const modelNames = {
  'claude-opus-5-5': 'Claude Opus 5.5 (best judgement)',
  'claude-sonnet-5-5': 'Claude Sonnet 5.5 (half the cost)',
  'claude-haiku-5-5': 'Claude Haiku 5.5 (cheapest, weakest feedback)',
};

/// Millionths of a dollar. An unlisted model (a fallback) is counted at the dearest rate.
int costMicrosFor(String model, {required int inTok, required int outTok, int cacheRead = 0, int cacheWrite = 0}) {
  final (i, o, r) = prices[model] ?? (10.0, 50.0, 1.0);
  return (inTok * i + cacheWrite * i * 1.25 + cacheRead * r + outTok * o).round();
}

class AiFailure implements Exception {
  const AiFailure(this.message, this.code);
  final String message, code;

  @override
  String toString() => message;
}

/// One turn of a conversation sent to the model.
class AiTurn {
  const AiTurn(this.role, this.text);
  const AiTurn.user(this.text) : role = 'user';
  const AiTurn.assistant(this.text) : role = 'assistant';
  final String role, text;
}

class AiClient {
  AiClient(this._store, {http.Client? client, this.url = 'https://api.anthropic.com/v1/messages'})
      : _http = client ?? http.Client();
  final Store _store;
  final http.Client _http;
  final String url;

  static const settingsKey = 'ai.settings';
  static const _timeout = Duration(minutes: 5);

  Future<AiSettings> settings() async => AiSettings.parse(await _store.setting(settingsKey));
  Future<void> saveSettings(AiSettings s) => _store.setSetting(settingsKey, jsonEncode(s.toJson()));

  Stream<int> watchMonthSpendMicros() {
    final n = DateTime.now().toUtc();
    final db = _store.db;
    return (db.select(db.aiCalls)..where((t) => t.createdAt.isBiggerOrEqualValue(DateTime.utc(n.year, n.month))))
        .watch()
        .map((rows) => rows.fold<int>(0, (a, r) => a + r.costMicros));
  }

  /// A reply constrained to [schema], decoded.
  Future<Json> structured({
    required String task,
    required String stable,
    String? instructions,
    required List<AiTurn> turns,
    required Map<String, Object?> schema,
    String effort = 'medium',
  }) async {
    final text = await _call(task: task, stable: stable, instructions: instructions, turns: turns, schema: schema, effort: effort);
    try {
      final j = jsonDecode(text);
      if (j is Json) return j;
    } on FormatException {
      // Falls through.
    }
    throw const AiFailure('The assistant didn\'t return what was asked for. Try again.', 'bad-json');
  }

  /// A plain-text reply (the interviewer, the tutor).
  Future<String> chat({
    required String task,
    required String stable,
    String? instructions,
    required List<AiTurn> turns,
    String effort = 'low',
  }) =>
      _call(task: task, stable: stable, instructions: instructions, turns: turns, effort: effort);

  /// [stable] is the part of the system prompt that repeats across calls (who
  /// the candidate is, the role, the resume). It is sent first and cached, so
  /// repeat calls in a sitting read it at a fraction of the price.
  /// [instructions] is what this call is for, and follows it.
  Future<String> _call({
    required String task,
    required String stable,
    String? instructions,
    required List<AiTurn> turns,
    Map<String, Object?>? schema,
    required String effort,
  }) async {
    final s = await settings();
    final key = s.claudeKey;
    if (key == null) throw const AiFailure('Add your Claude API key in Settings first.', 'no-key');
    final spent = await watchMonthSpendMicros().first;
    if (spent >= s.monthlyCapUsd * 1000000) {
      throw AiFailure('This month\'s budget of \$${s.monthlyCapUsd.toStringAsFixed(2)} is used up. Settings can raise it.', 'cap');
    }
    final sw = Stopwatch()..start();
    final model = s.model;
    Future<Never> fail(String message, String code, {int cost = 0, int inTok = 0, int outTok = 0}) async {
      await _log(model, task, sw, 'error', error: code, cost: cost, inTok: inTok, outTok: outTok);
      throw AiFailure(message, code);
    }

    final http.Response r;
    try {
      r = await _http
          .post(
            Uri.parse(url),
            headers: {
              'content-type': 'application/json',
              'x-api-key': key,
              'anthropic-version': '2026-10-21',
              // A safety decline is re-run on another model inside the same call.
              'anthropic-beta': 'server-side-fallback-2026-07-01',
            },
            body: jsonEncode({
              'model': model,
              'max_tokens': 16000,
              'fallbacks': 'default',
              'system': [
                {
                  'type': 'text',
                  'text': stable,
                  'cache_control': {'type': 'ephemeral'},
                },
                if (instructions != null) {'type': 'text', 'text': instructions},
              ],
              'output_config': {
                'effort': effort,
                if (schema != null) 'format': {'type': 'json_schema', 'schema': schema},
              },
              'messages': [
                for (final t in turns) {'role': t.role, 'content': t.text},
              ],
            }),
          )
          .timeout(_timeout);
    } on TimeoutException {
      return fail('The assistant took too long to answer.', 'timeout');
    } on SocketException {
      return fail('Couldn\'t reach the assistant. Check your connection.', 'offline');
    } on http.ClientException {
      return fail('Couldn\'t reach the assistant. Check your connection.', 'offline');
    } on HandshakeException {
      return fail('Couldn\'t reach the assistant securely. Check your connection and the PC\'s clock.', 'offline');
    }
    if (r.statusCode == 401) return fail('The API key in Settings wasn\'t accepted.', 'bad-key');
    if (r.statusCode == 429) return fail('The assistant is rate limiting this key; try again shortly.', 'rate-limit');
    if (r.statusCode != 200) {
      var detail = '';
      try {
        final e = jsonDecode(utf8.decode(r.bodyBytes));
        if (e is Map && e['error'] is Map) detail = ': ${e['error']['message']}';
      } on FormatException {
        // No detail to show.
      }
      return fail('The assistant answered with an error (${r.statusCode})$detail', 'http-${r.statusCode}');
    }

    final Object? body;
    try {
      body = jsonDecode(utf8.decode(r.bodyBytes));
    } on FormatException {
      return fail('The assistant sent something unreadable.', 'bad-response');
    }
    if (body is! Map) return fail('The assistant sent something unreadable.', 'bad-response');
    final usage = body['usage'] as Map? ?? const {};
    int tok(String k) => (usage[k] as num?)?.toInt() ?? 0;
    final inTok = tok('input_tokens'), outTok = tok('output_tokens');
    final cacheRead = tok('cache_read_input_tokens'), cacheWrite = tok('cache_creation_input_tokens');
    final used = body['model'] is String ? body['model'] as String : model;
    final cost = costMicrosFor(used, inTok: inTok, outTok: outTok, cacheRead: cacheRead, cacheWrite: cacheWrite);
    final stop = body['stop_reason'];
    if (stop == 'refusal') return fail('The assistant declined to work on this.', 'refused', cost: cost, inTok: inTok, outTok: outTok);
    if (stop == 'max_tokens') return fail('The assistant ran out of room before finishing.', 'max-tokens', cost: cost, inTok: inTok, outTok: outTok);
    final text = [
      for (final b in (body['content'] as List? ?? const []))
        if (b is Map && b['type'] == 'text' && b['text'] is String) b['text'] as String,
    ].join();
    await _log(used, task, sw, 'ok', cost: cost, inTok: inTok + cacheWrite, outTok: outTok, cacheRead: cacheRead);
    return text;
  }

  Future<void> _log(String model, String task, Stopwatch sw, String status,
      {String? error, int cost = 0, int inTok = 0, int outTok = 0, int cacheRead = 0}) async {
    final db = _store.db;
    await db.into(db.aiCalls).insert(AiCallsCompanion.insert(
          id: newId(),
          createdAt: nowUtc(),
          model: model,
          task: task,
          latencyMs: Value(sw.elapsedMilliseconds),
          inTok: Value(inTok),
          outTok: Value(outTok),
          cacheReadTok: Value(cacheRead),
          costMicros: Value(cost),
          status: status,
          errorCode: Value(error),
        ));
  }
}

final aiClientProvider = Provider<AiClient>((ref) => AiClient(ref.watch(storeProvider)));

final aiSettingsProvider = StreamProvider<AiSettings>(
    (ref) => ref.watch(storeProvider).watchSetting(AiClient.settingsKey).map(AiSettings.parse));

final aiMonthSpendProvider = StreamProvider.autoDispose<int>((ref) => ref.watch(aiClientProvider).watchMonthSpendMicros());
