import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

/// Mono 16-bit PCM at 16 kHz: what the recogniser wants and what we record.
const captureSampleRate = 16000;

/// Writes a mono PCM16 WAV as the audio arrives, so a crash leaves a file
/// whose samples are all there; only the two size fields are stale, and
/// [repairWav] fixes them.
class WavWriter {
  WavWriter._(this._raf);

  final RandomAccessFile _raf;
  var _bytes = 0;
  var _sinceFlush = 0;

  static Future<WavWriter> create(File file) async {
    await file.parent.create(recursive: true);
    final raf = await file.open(mode: FileMode.write);
    raf.writeFromSync(wavHeader(0));
    return WavWriter._(raf);
  }

  /// Audio written so far.
  Duration get length => Duration(microseconds: _bytes * 1000000 ~/ (captureSampleRate * 2));

  void add(Uint8List pcm) {
    _raf.writeFromSync(pcm);
    _bytes += pcm.length;
    _sinceFlush += pcm.length;
    // About once a second, so a crash loses at most a second.
    if (_sinceFlush >= captureSampleRate * 2) {
      _raf.flushSync();
      _sinceFlush = 0;
    }
  }

  Future<void> close() async {
    _raf.setPositionSync(0);
    _raf.writeFromSync(wavHeader(_bytes));
    await _raf.close();
  }
}

/// The 44-byte header of a mono PCM16 16 kHz WAV holding [dataBytes].
Uint8List wavHeader(int dataBytes) {
  final b = ByteData(44);
  void tag(int at, String s) {
    for (var i = 0; i < 4; i++) {
      b.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  tag(0, 'RIFF');
  b.setUint32(4, 36 + dataBytes, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  b.setUint32(16, 16, Endian.little);
  b.setUint16(20, 1, Endian.little); // PCM
  b.setUint16(22, 1, Endian.little); // mono
  b.setUint32(24, captureSampleRate, Endian.little);
  b.setUint32(28, captureSampleRate * 2, Endian.little);
  b.setUint16(32, 2, Endian.little);
  b.setUint16(34, 16, Endian.little);
  tag(36, 'data');
  b.setUint32(40, dataBytes, Endian.little);
  return b.buffer.asUint8List();
}

/// Rewrites the size fields of a WAV we wrote from its real length (after a
/// crash). Returns the audio length, or null if the file isn't ours.
Future<Duration?> repairWav(File file) async {
  if (!await file.exists()) return null;
  final raf = await file.open(mode: FileMode.append);
  try {
    final len = await raf.length();
    if (len < 44) return null;
    await raf.setPosition(0);
    final head = await raf.read(4);
    if (String.fromCharCodes(head) != 'RIFF') return null;
    // Drop a half-written sample at the end.
    final data = (len - 44) & ~1;
    await raf.setPosition(0);
    await raf.writeFrom(wavHeader(data));
    if (44 + data != len) await raf.truncate(44 + data);
    return Duration(microseconds: data * 1000000 ~/ (captureSampleRate * 2));
  } finally {
    await raf.close();
  }
}

/// Little-endian PCM16 bytes to samples in -1..1.
Float32List pcm16ToFloat(Uint8List bytes) {
  final n = bytes.length ~/ 2;
  final bd = ByteData.sublistView(bytes);
  final out = Float32List(n);
  for (var i = 0; i < n; i++) {
    out[i] = bd.getInt16(i * 2, Endian.little) / 32768.0;
  }
  return out;
}

/// Loudness of a PCM16 chunk as 0..1 for a level meter (RMS on a -60..0 dBFS scale).
double pcmLevel(Uint8List bytes) {
  final n = bytes.length ~/ 2;
  if (n == 0) return 0;
  final bd = ByteData.sublistView(bytes);
  var sum = 0.0;
  for (var i = 0; i < n; i++) {
    final s = bd.getInt16(i * 2, Endian.little) / 32768.0;
    sum += s * s;
  }
  final rms = math.sqrt(sum / n);
  if (rms <= 0) return 0;
  final db = 20 * math.log(rms) / math.ln10;
  return ((db + 60) / 60).clamp(0.0, 1.0);
}

/// Reads the samples of a WAV, walking its chunks (Windows' recorder adds a
/// `JUNK` chunk). Only mono PCM16 at 16 kHz is accepted; null otherwise.
Float32List? readPcm16Wav(Uint8List b) {
  if (b.length < 12 || String.fromCharCodes(b.sublist(0, 4)) != 'RIFF' || String.fromCharCodes(b.sublist(8, 12)) != 'WAVE') return null;
  final bd = ByteData.sublistView(b);
  var at = 12;
  int? channels, bits, rate;
  while (at + 8 <= b.length) {
    final id = String.fromCharCodes(b.sublist(at, at + 4));
    var size = bd.getUint32(at + 4, Endian.little);
    final body = at + 8;
    if (id == 'fmt ' && body + 16 <= b.length) {
      channels = bd.getUint16(body + 2, Endian.little);
      rate = bd.getUint32(body + 4, Endian.little);
      bits = bd.getUint16(body + 14, Endian.little);
    } else if (id == 'data') {
      if (channels != 1 || bits != 16 || rate != captureSampleRate) return null;
      // A crashed file may claim more than it holds.
      if (body + size > b.length) size = b.length - body;
      return pcm16ToFloat(Uint8List.sublistView(b, body, body + (size & ~1)));
    }
    at = body + size + (size & 1);
  }
  return null;
}
