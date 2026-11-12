// From Soloza's `core/capture/speech_models.dart`: pinned, checksummed model
// downloads. English only here, plus an import from a folder of models.
import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;


/// One file of a speech model: where it comes from and what it must be.
class SpeechModelFile {
  const SpeechModelFile(this.name, this.url, this.bytes, this.sha256);
  final String name;
  final String url;
  final int bytes;
  final String sha256;
}

/// An on-device speech model, downloaded on first use. Sources are pinned to
/// a commit and every file is checked by size and SHA-256 before use.
/// Spike results and sources: `docs/research/academy/F-platform-stack.md` §10.6.
class SpeechModel {
  const SpeechModel({required this.id, required this.label, required this.credit, required this.files});
  final String id;
  final String label;

  /// Licence and author, shown in Settings → Voice.
  final String credit;
  final List<SpeechModelFile> files;

  int get bytes => files.fold(0, (a, f) => a + f.bytes);
}

const _parakeet = 'https://huggingface.co/csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8/resolve/1ab9323565ddb038682214b292f588070a538ce2';

/// Finds where speech starts and stops; needed by every language.
const vadModel = SpeechModel(
  id: 'silero-vad',
  label: 'Speech detector',
  credit: 'Silero VAD, MIT licence',
  files: [
    SpeechModelFile('silero_vad.onnx', 'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx', 643854,
        '9e2449e1087496d8d4caba907f23e0bd3f78d91fa552479bb9c23ac09cbb1fd6'),
  ],
);

const englishModel = SpeechModel(
  id: 'parakeet-tdt-0.6b-v2-int8',
  label: 'English',
  credit: 'Parakeet TDT 0.6B v2 by NVIDIA, CC BY 4.0 (int8 conversion by the sherpa-onnx project)',
  files: [
    SpeechModelFile('encoder.int8.onnx', '$_parakeet/encoder.int8.onnx', 652184296, 'a32b12d17bbbc309d0686fbbcc2987b5e9b8333a7da83fa6b089f0a2acd651ab'),
    SpeechModelFile('decoder.int8.onnx', '$_parakeet/decoder.int8.onnx', 7257753, 'b6bb64963457237b900e496ee9994b59294526439fbcc1fecf705b31a15c6b4e'),
    SpeechModelFile('joiner.int8.onnx', '$_parakeet/joiner.int8.onnx', 1739080, '7946164367946e7f9f29a122407c3252b680dbae9a51343eb2488d057c3c43d2'),
    SpeechModelFile('tokens.txt', '$_parakeet/tokens.txt', 9384, 'ec182b70dd42113aff6c5372c75cac58c952443eb22322f57bbd7f53977d497d'),
  ],
);

/// What English transcription needs.
const speechModels = [vadModel, englishModel];

/// SHA-256 of a file, read in a background isolate (top-level so the
/// isolate captures nothing else).
Future<String> sha256OfFileInBackground(String path) => Isolate.run(() => _sha256OfFile(path));

Future<String> _sha256OfFile(String path) async => (await sha256.bind(File(path).openRead()).first).toString();

/// Bytes downloaded so far out of the total.
typedef InstallProgress = ({int done, int total});

class SpeechModelStore {
  SpeechModelStore(this.dir, this._client,
      {Future<String> Function(String path)? hash, this.connectTimeout = const Duration(seconds: 15), this.idleTimeout = const Duration(seconds: 30)})
      : _hash = hash ?? sha256OfFileInBackground;

  /// How long the server may take to answer, and how long a started download
  /// may go without a byte. A dead connection with no reset (Wi-Fi drop, sleep
  /// and resume) otherwise hangs the install, and Cancel with it (E16 #2).
  final Duration connectTimeout, idleTimeout;

  final Directory dir;
  final http.Client _client;
  final Future<String> Function(String path) _hash;

  Directory dirOf(SpeechModel m) => Directory(p.join(dir.path, m.id));
  String pathOf(SpeechModel m, String name) => p.join(dir.path, m.id, name);

  /// Every file is in place with its expected size (each was hash-checked
  /// before it got its final name).
  bool isInstalled(SpeechModel m) => m.files.every((f) {
        final file = File(pathOf(m, f.name));
        return file.existsSync() && file.lengthSync() == f.bytes;
      });

  /// Downloads what is missing, resuming a partial file. Each file is
  /// written as `.part`, checked by size and SHA-256, then renamed, so a
  /// half-downloaded or wrong file is never used. [cancelled] stops between
  /// chunks (the `.part` stays for the next try).
  Stream<InstallProgress> install(SpeechModel m, {bool Function()? cancelled}) async* {
    await dirOf(m).create(recursive: true);
    final total = m.bytes;
    var before = 0;
    for (final f in m.files) {
      final target = File(pathOf(m, f.name));
      if (target.existsSync() && target.lengthSync() == f.bytes) {
        before += f.bytes;
        yield (done: before, total: total);
        continue;
      }
      final part = File('${target.path}.part');
      var have = part.existsSync() ? part.lengthSync() : 0;
      if (have > f.bytes) {
        part.deleteSync();
        have = 0;
      }
      if (have < f.bytes) {
        final req = http.Request('GET', Uri.parse(f.url));
        if (have > 0) req.headers['Range'] = 'bytes=$have-';
        final res = await _client.send(req).timeout(connectTimeout);
        if (res.statusCode == 200) {
          have = 0; // the server ignored the range: start over
        } else if (res.statusCode != 206) {
          await res.stream.drain<void>();
          throw HttpException('The download of ${m.label} failed (HTTP ${res.statusCode}).');
        }
        final sink = part.openWrite(mode: have == 0 ? FileMode.write : FileMode.append);
        var sinceYield = 0;
        try {
          await for (final chunk in res.stream.timeout(idleTimeout)) {
            sink.add(chunk);
            have += chunk.length;
            sinceYield += chunk.length;
            if (cancelled?.call() ?? false) break;
            if (sinceYield >= 1 << 20) {
              sinceYield = 0;
              yield (done: before + have, total: total);
            }
          }
        } finally {
          await sink.close();
        }
        if (cancelled?.call() ?? false) return;
      }
      if (part.lengthSync() != f.bytes) {
        throw HttpException('The download of ${m.label} ended early; try again to resume it.');
      }
      if (await _hash(part.path) != f.sha256) {
        part.deleteSync();
        throw StateError('${m.label}: a downloaded file did not match its checksum and was removed. Try again.');
      }
      if (target.existsSync()) target.deleteSync();
      part.renameSync(target.path);
      before += f.bytes;
      yield (done: before, total: total);
    }
  }

  Future<void> delete(SpeechModel m) async {
    final d = dirOf(m);
    if (d.existsSync()) await d.delete(recursive: true);
  }
}

/// Where speech models live (set in `main`, overridden in tests).
final speechModelDirProvider = Provider<Directory>((ref) => throw UnimplementedError());

final speechModelStoreProvider = Provider<SpeechModelStore>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return SpeechModelStore(ref.watch(speechModelDirProvider), client);
});

/// A model's state in Settings and on the record button.
sealed class ModelState {
  const ModelState();
}

class ModelMissing extends ModelState {
  const ModelMissing([this.error]);
  final String? error;
}

class ModelInstalling extends ModelState {
  const ModelInstalling(this.done, this.total);
  final int done, total;
}

class ModelReady extends ModelState {
  const ModelReady();
}

/// Install state of every model, and the one place downloads start, so two
/// buttons can't download the same model twice.
class SpeechModelsController extends Notifier<Map<String, ModelState>> {
  final _cancel = <String>{};

  SpeechModelStore get _store => ref.read(speechModelStoreProvider);

  @override
  Map<String, ModelState> build() {
    final store = ref.watch(speechModelStoreProvider);
    return {
      for (final m in speechModels) m.id: store.isInstalled(m) ? const ModelReady() : const ModelMissing(),
    };
  }

  bool get ready => speechModels.every((m) => state[m.id] is ModelReady);

  /// Installs everything transcription needs. Returns null on success, else why not.
  Future<String?> installAll() async {
    for (final m in speechModels) {
      final err = await install(m);
      if (err != null) return err;
    }
    return null;
  }

  /// Copies models from a folder that already holds them (one subfolder per
  /// model id, as this app and Soloza lay them out), checking each file's
  /// size and SHA-256. Returns null on success, else why not.
  Future<String?> importFrom(Directory folder) async {
    for (final m in speechModels) {
      if (state[m.id] is ModelReady) continue;
      _set(m.id, ModelInstalling(0, m.bytes));
      try {
        var done = 0;
        await _store.dirOf(m).create(recursive: true);
        for (final f in m.files) {
          final src = File(p.join(folder.path, m.id, f.name));
          if (!src.existsSync() || src.lengthSync() != f.bytes) throw StateError('${m.label}: ${f.name} was not found in that folder.');
          if (await sha256OfFileInBackground(src.path) != f.sha256) throw StateError('${m.label}: ${f.name} in that folder is not the expected file.');
          await src.copy(_store.pathOf(m, f.name));
          done += f.bytes;
          _set(m.id, ModelInstalling(done, m.bytes));
        }
        _set(m.id, const ModelReady());
      } on Object catch (e) {
        final msg = e is StateError ? e.message : '$e';
        _set(m.id, ModelMissing(msg));
        return msg;
      }
    }
    return null;
  }

  Future<String?> install(SpeechModel m) async {
    if (state[m.id] is ModelReady) return null;
    if (state[m.id] is ModelInstalling) {
      // Another caller started it: wait for the outcome.
      while (state[m.id] is ModelInstalling) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      return switch (state[m.id]) { ModelReady() => null, ModelMissing(:final error) => error ?? 'Download stopped.', _ => null };
    }
    _cancel.remove(m.id);
    _set(m.id, ModelInstalling(0, m.bytes));
    try {
      await for (final pr in _store.install(m, cancelled: () => _cancel.contains(m.id))) {
        _set(m.id, ModelInstalling(pr.done, pr.total));
      }
      if (_cancel.contains(m.id)) {
        _set(m.id, const ModelMissing('Download paused; it resumes where it stopped.'));
        return 'Download paused.';
      }
      _set(m.id, const ModelReady());
      return null;
    } on Object catch (e) {
      // A dead or intercepted connection reads the same to the owner (E16 #2).
      final offline = e is SocketException || e is TimeoutException || e is http.ClientException || e is HandshakeException;
      final msg = offline
          ? 'No connection. The download resumes where it stopped when you try again.'
          : e is HttpException
              ? e.message
              : (e is StateError ? e.message : '$e');
      _set(m.id, ModelMissing(msg));
      return msg;
    }
  }

  void cancel(SpeechModel m) => _cancel.add(m.id);

  Future<void> remove(SpeechModel m) async {
    await _store.delete(m);
    _set(m.id, const ModelMissing());
  }

  void _set(String id, ModelState s) => state = {...state, id: s};
}

final speechModelsProvider = NotifierProvider<SpeechModelsController, Map<String, ModelState>>(SpeechModelsController.new);
