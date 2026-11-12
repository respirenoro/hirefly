import 'dart:async';
import 'dart:convert';
import 'dart:io';


/// One installed Windows voice.
class SpeechVoice {
  const SpeechVoice({required this.id, required this.name, required this.language});
  final String id;
  final String name;
  final String language;
}

/// What the speech host reports, one per line on its stdout.
sealed class ReadAloudEvent {
  const ReadAloudEvent();
}

class ReadAloudReady extends ReadAloudEvent {
  const ReadAloudReady();
}

class ReadAloudVoices extends ReadAloudEvent {
  const ReadAloudVoices(this.voices);
  final List<SpeechVoice> voices;
}

class ReadAloudStarted extends ReadAloudEvent {
  const ReadAloudStarted();
}

class ReadAloudDone extends ReadAloudEvent {
  const ReadAloudDone();
}

class ReadAloudError extends ReadAloudEvent {
  const ReadAloudError(this.message);
  final String message;
}

/// Parses one stdout line of the host; null for a line that is not an event.
ReadAloudEvent? parseReadAloudEvent(String line) {
  final l = line.trim();
  if (l == 'ready') return const ReadAloudReady();
  if (l == 'started') return const ReadAloudStarted();
  if (l == 'done') return const ReadAloudDone();
  if (l.startsWith('error ')) return ReadAloudError(l.substring(6));
  if (l.startsWith('voices ')) {
    try {
      final raw = jsonDecode(l.substring(7)) as List<dynamic>;
      return ReadAloudVoices([
        for (final v in raw)
          SpeechVoice(
            id: (v as Map<String, dynamic>)['id'] as String,
            name: v['name'] as String,
            language: v['lang'] as String,
          ),
      ]);
    } catch (_) {
      return const ReadAloudError('unreadable voice list');
    }
  }
  return null;
}

/// Splits text into pieces to speak one after another: whole sentences where
/// possible, never longer than [max] characters, blank lines always break.
/// Pieces are trimmed and never empty.
List<String> chunkForSpeech(String text, {int max = 400}) {
  final out = <String>[];
  for (final para in text.split(RegExp(r'\n\s*\n'))) {
    final p = para.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (p.isEmpty) continue;
    var cur = '';
    // A sentence ends at . ! ? or … (and closing quotes/brackets) before a space.
    for (final s in p.split(RegExp(r'(?<=[.!?…][)"”’]?)\s+'))) {
      if (cur.isNotEmpty && cur.length + 1 + s.length > max) {
        out.add(cur);
        cur = '';
      }
      cur = cur.isEmpty ? s : '$cur $s';
      while (cur.length > max) {
        var cut = cur.lastIndexOf(' ', max);
        if (cut <= 0) cut = max;
        out.add(cur.substring(0, cut).trim());
        cur = cur.substring(cut).trim();
      }
    }
    if (cur.isNotEmpty) out.add(cur);
  }
  return out;
}

/// The playback volume the reader starts the host with (0 to 1). Real-app tests
/// set it to 0 so a run makes no sound.
double readAloudVolume = 1;

/// Reads text aloud with Windows' own voices (WinRT `SpeechSynthesizer`, on
/// device, no download), through one long-lived PowerShell host. The host
/// leaves when the app's process is gone, so it never outlives the app. Commands
/// reach it through a small file it tails (a child's stdin did not work).
class ReadAloud {
  ReadAloud();

  Process? _proc;
  File? _cmd;
  final _events = StreamController<ReadAloudEvent>.broadcast();
  Completer<void>? _ready;
  Completer<List<SpeechVoice>>? _voices;
  List<String> _queue = const [];
  int _next = 0;
  bool _reading = false;
  final _index = StreamController<int>.broadcast();

  /// Events from the host (for tests and the UI).
  Stream<ReadAloudEvent> get events => _events.stream;

  /// The index of the piece being spoken (see [readAll]); -1 once finished.
  Stream<int> get currentIndex => _index.stream;

  bool get isRunning => _proc != null;

  /// Starts the host. Returns null when it is ready, else the reason it is not
  /// available (not Windows, no PowerShell, WinRT speech missing).
  Future<String?> start({double? volume}) async {
    volume ??= readAloudVolume;
    if (_proc != null) return null;
    if (!Platform.isWindows) return 'Read aloud needs Windows.';
    try {
      final dir = await Directory.systemTemp.createTemp('terra_tts_');
      final cmd = _cmd = File('${dir.path}/commands.txt')..writeAsStringSync('');
      final p = await Process.start('powershell', [
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-EncodedCommand',
        base64Encode16(readAloudHostScript(cmd.path, pid)),
      ]);
      _proc = p;
      _ready = Completer<void>();
      p.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen(_line);
      p.stderr.drain<void>();
      unawaited(p.exitCode.then((_) {
        if (identical(_proc, p)) _proc = null;
        _reading = false;
        if (!(_ready?.isCompleted ?? true)) _ready!.completeError('exited');
      }));
      await _ready!.future.timeout(const Duration(seconds: 20));
      if (volume != 1) _send('volume $volume');
      return null;
    } on Object catch (e) {
      await dispose();
      return 'Read aloud could not start: $e';
    }
  }

  void _line(String line) {
    final e = parseReadAloudEvent(line);
    if (e == null) return;
    if (e is ReadAloudReady) {
      if (!(_ready?.isCompleted ?? true)) _ready!.complete();
    } else if (e is ReadAloudVoices) {
      _voices?.complete(e.voices);
      _voices = null;
    } else if (e is ReadAloudDone && _reading) {
      _speakNext();
    }
    if (!_events.isClosed) _events.add(e);
  }

  void _send(String command) {
    try {
      if (_proc != null) _cmd?.writeAsStringSync('$command\n', mode: FileMode.append, flush: true);
    } on Object {
      // The host is gone; its exit handler resets the state.
    }
  }

  /// The installed voices, empty when the host is not running.
  Future<List<SpeechVoice>> voices() async {
    if (_proc == null) return const [];
    _voices = Completer<List<SpeechVoice>>();
    _send('voices');
    return _voices!.future.timeout(const Duration(seconds: 10), onTimeout: () => const []);
  }

  /// Speaking speed, 0.5 to 3 (1 is normal).
  void setRate(double rate) => _send('rate ${rate.clamp(0.5, 3.0)}');

  void setVoice(String id) => _send('voice ${base64.encode(utf8.encode(id))}');

  /// Speaks one text now, replacing what is being spoken.
  void speak(String text) {
    _reading = false;
    _say(text);
  }

  void _say(String text) => _send('speak ${base64.encode(utf8.encode(text))}');

  /// Speaks the pieces one after another, from [from]; [currentIndex] reports
  /// the one being spoken.
  void readAll(List<String> pieces, {int from = 0}) {
    _queue = pieces;
    _next = from;
    _reading = true;
    _speakNext();
  }

  void _speakNext() {
    if (_next >= _queue.length) {
      _reading = false;
      _index.add(-1);
      return;
    }
    _index.add(_next);
    _say(_queue[_next++]);
  }

  void pause() => _send('pause');
  void resume() => _send('resume');

  /// Stops speaking; no further piece is read and no `done` event follows.
  void stop() {
    _reading = false;
    _send('stop');
    _index.add(-1);
  }

  Future<void> dispose() async {
    final p = _proc;
    _proc = null;
    _reading = false;
    if (p != null) {
      try {
        _cmd?.writeAsStringSync('quit\n', mode: FileMode.append, flush: true);
      } on Object {
        // already gone
      }
      // A host that does not leave on its own is ended; it is ours.
      unawaited(p.exitCode.timeout(const Duration(seconds: 3), onTimeout: () {
        p.kill();
        return 0;
      }).whenComplete(() {
        try {
          _cmd?.parent.deleteSync(recursive: true);
        } on Object {
          // a leftover temp folder is harmless
        }
      }));
    }
    await _events.close();
    await _index.close();
  }
}

/// The PowerShell speech host. Commands (one per line, appended to [cmdFile]):
/// `speak <b64>`, `pause`, `resume`, `stop`, `rate <n>`, `voice <b64 id>`,
/// `voices`, `volume <0-1>`, `quit`. Events (one per line on stdout): `ready`,
/// `voices <json>`, `started`, `done`, `error <text>`. PowerShell 5.1 cannot
/// subscribe to WinRT events, so the end of a piece is found by polling the
/// position. The host exits when [parentPid] is gone.
String readAloudHostScript(String cmdFile, int parentPid) =>
    "\$cmdFile = '${cmdFile.replaceAll("'", "''")}'\n\$parentPid = $parentPid\n$_hostBody";

const _hostBody = r'''
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
function Emit($s) { [Console]::Out.WriteLine($s); [Console]::Out.Flush() }
try {
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$null = [Windows.Media.SpeechSynthesis.SpeechSynthesizer, Windows.Media.SpeechSynthesis, ContentType=WindowsRuntime]
$null = [Windows.Media.SpeechSynthesis.SpeechSynthesisStream, Windows.Media.SpeechSynthesis, ContentType=WindowsRuntime]
$null = [Windows.Media.Playback.MediaPlayer, Windows.Media, ContentType=WindowsRuntime]
$null = [Windows.Media.Core.MediaSource, Windows.Media, ContentType=WindowsRuntime]
$asTask = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
function Await($op, [Type]$t) { $m = $asTask.MakeGenericMethod($t); $task = $m.Invoke($null, @($op)); $task.Wait(-1) | Out-Null; $task.Result }
function Utf8($b64) { [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64)) }
$synth = New-Object Windows.Media.SpeechSynthesis.SpeechSynthesizer
$player = New-Object Windows.Media.Playback.MediaPlayer
$playing = $false
$paused = $false
$fs = [System.IO.File]::Open($cmdFile, 'OpenOrCreate', 'Read', 'ReadWrite')
$reader = New-Object System.IO.StreamReader($fs, (New-Object System.Text.UTF8Encoding($false)))
$tick = 0
Emit 'ready'
while ($true) {
  $line = $reader.ReadLine()
  if ($null -eq $line) {
    Start-Sleep -Milliseconds 40
    $tick++
    if ($tick % 25 -eq 0 -and $null -eq (Get-Process -Id $parentPid -ErrorAction SilentlyContinue)) { break }
  } else {
    $sp = $line.IndexOf(' ')
    if ($sp -lt 0) { $cmd = $line; $arg = '' } else { $cmd = $line.Substring(0, $sp); $arg = $line.Substring($sp + 1) }
    try {
      switch ($cmd) {
        'quit' { $player.Pause(); exit 0 }
        'speak' {
          $player.Pause()
          $st = Await ($synth.SynthesizeTextToStreamAsync((Utf8 $arg))) ([Windows.Media.SpeechSynthesis.SpeechSynthesisStream])
          $player.Source = [Windows.Media.Core.MediaSource]::CreateFromStream($st, $st.ContentType)
          $paused = $false
          $playing = $true
          $player.Play()
          Emit 'started'
        }
        'pause' { if ($playing) { $paused = $true; $player.Pause() } }
        'resume' { if ($playing) { $paused = $false; $player.Play() } }
        'stop' { $playing = $false; $paused = $false; $player.Pause() }
        'rate' { $synth.Options.SpeakingRate = [double]::Parse($arg, [Globalization.CultureInfo]::InvariantCulture) }
        'volume' { $player.Volume = [double]::Parse($arg, [Globalization.CultureInfo]::InvariantCulture) }
        'voice' {
          $id = Utf8 $arg
          $v = [Windows.Media.SpeechSynthesis.SpeechSynthesizer]::AllVoices | Where-Object { $_.Id -eq $id } | Select-Object -First 1
          if ($null -ne $v) { $synth.Voice = $v } else { Emit 'error voice not installed' }
        }
        'voices' {
          $list = @([Windows.Media.SpeechSynthesis.SpeechSynthesizer]::AllVoices | ForEach-Object { @{ id = $_.Id; name = $_.DisplayName; lang = $_.Language } })
          Emit ('voices ' + (ConvertTo-Json -InputObject $list -Compress))
        }
      }
    } catch { Emit ('error ' + ($_.Exception.Message -replace '\s+', ' ')) ; $playing = $false }
  }
  if ($playing -and -not $paused) {
    $ss = $player.PlaybackSession
    $d = $ss.NaturalDuration.TotalMilliseconds
    if ($d -gt 0 -and ($ss.Position.TotalMilliseconds -ge $d - 120 -or $ss.PlaybackState -eq 'Paused')) {
      $playing = $false
      Emit 'done'
    }
  }
}
} catch { Emit ('error ' + ($_.Exception.Message -replace '\s+', ' ')); exit 2 }
''';

/// PowerShell's -EncodedCommand wants base64 of UTF-16LE (from Soloza's `start_shortcut.dart`).
String base64Encode16(String s) {
  final bytes = <int>[for (final u in s.codeUnits) ...[u & 0xff, u >> 8]];
  return base64.encode(bytes);
}
