import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:project_hirefly/ui/ui.dart';

void main() {
  Future<ScrollController> page(WidgetTester t) async {
    await t.pumpWidget(MaterialApp(
      theme: appTheme(),
      home: Scaffold(body: Sheet(children: [for (var i = 0; i < 80; i++) SizedBox(height: 40, child: Text('Line $i'))])),
    ));
    return t.widget<SingleChildScrollView>(find.byType(SingleChildScrollView)).controller!;
  }

  testWidgets('click the wheel, move away, and the page glides; click again and it stops', (t) async {
    final c = await page(t);
    final mouse = await t.createGesture(kind: PointerDeviceKind.mouse, buttons: kMiddleMouseButton);
    await mouse.addPointer(location: const Offset(400, 200));
    await mouse.down(const Offset(400, 200));
    await t.pump(const Duration(milliseconds: 50));
    await mouse.up();
    await t.pump();
    expect(find.byIcon(Icons.unfold_more), findsOneWidget, reason: 'the anchor mark shows while gliding');
    expect(c.offset, 0, reason: 'nothing moves inside the dead zone');

    await mouse.moveTo(const Offset(400, 320));
    await t.pump(const Duration(milliseconds: 100));
    await t.pump(const Duration(milliseconds: 500));
    final down = c.offset;
    expect(down, greaterThan(100));

    await mouse.moveTo(const Offset(400, 120));
    await t.pump(const Duration(milliseconds: 100));
    await t.pump(const Duration(milliseconds: 300));
    expect(c.offset, lessThan(down), reason: 'above the anchor it scrolls back up');

    await mouse.down(const Offset(400, 120));
    await mouse.up();
    await t.pump();
    expect(find.byIcon(Icons.unfold_more), findsNothing);
    final stopped = c.offset;
    await t.pump(const Duration(milliseconds: 400));
    expect(c.offset, stopped);
  });

  testWidgets('holding the wheel and dragging scrolls, and stops on release', (t) async {
    final c = await page(t);
    final mouse = await t.createGesture(kind: PointerDeviceKind.mouse, buttons: kMiddleMouseButton);
    await mouse.addPointer(location: const Offset(400, 200));
    await mouse.down(const Offset(400, 200));
    await mouse.moveTo(const Offset(400, 330));
    // Frames as a display delivers them; the glide ignores a gap longer than a fifth of a second.
    for (var i = 0; i < 5; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(c.offset, greaterThan(50));
    await mouse.up();
    await t.pump();
    expect(find.byIcon(Icons.unfold_more), findsNothing);
  });

  testWidgets('an ordinary left click neither starts nor is swallowed', (t) async {
    final c = await page(t);
    await t.tapAt(const Offset(400, 200));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.byIcon(Icons.unfold_more), findsNothing);
    expect(c.offset, 0);
  });
}
