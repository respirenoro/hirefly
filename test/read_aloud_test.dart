// The Windows voice host ported from Soloza starts, speaks and stops. Run at
// volume 0, so the test makes no sound.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:project_hirefly/terra/read_aloud.dart';

void main() {
  test('speaks a line with a Windows voice and reports when it is done', () async {
    final r = ReadAloud();
    addTearDown(r.dispose);
    expect(await r.start(volume: 0), isNull);
    expect(await r.voices(), isNotEmpty);
    final done = r.events.firstWhere((e) => e is ReadAloudDone).timeout(const Duration(seconds: 30));
    r.speak('Tell me about yourself.');
    await done;
  }, skip: !Platform.isWindows, timeout: const Timeout(Duration(seconds: 90)));
}
