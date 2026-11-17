// The pointing hand over buttons (widgets/pointer.dart): over enabled buttons, rail destinations,
// InkWells and switches; the arrow over disabled buttons and plain space; a text field's own cursor.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uwufix/widgets/pointer.dart';

void main() {
  testWidgets('the hand over what can be clicked, and only there', (tester) async {
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) {
        return PointerOverButtons(child: child!);
      },
      home: Scaffold(
        body: Row(children: [
          NavigationRail(
            selectedIndex: 0,
            onDestinationSelected: (_) {},
            labelType: NavigationRailLabelType.all,
            destinations: const [
              NavigationRailDestination(icon: Icon(Icons.home), label: Text('Home')),
              NavigationRailDestination(icon: Icon(Icons.history), label: Text('History')),
            ],
          ),
          Expanded(
            child: Column(children: [
              FilledButton(onPressed: () {}, child: const Text('On')),
              const FilledButton(onPressed: null, child: Text('Off')),
              IconButton(onPressed: () {}, icon: const Icon(Icons.copy)),
              InkWell(onTap: () {}, child: const SizedBox(width: 100, height: 40, child: Text('Ink'))),
              Switch(value: true, onChanged: (_) {}),
              const SizedBox(width: 200, child: TextField()),
              const SizedBox(height: 40, child: Text('Plain')),
            ]),
          ),
        ]),
      ),
    ));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    Future<MouseCursor?> cursorOver(Finder finder) async {
      await mouse.moveTo(tester.getCenter(finder));
      await tester.pump();
      await tester.pump();
      return RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1);
    }

    expect(await cursorOver(find.text('History')), SystemMouseCursors.click);
    expect(await cursorOver(find.byIcon(Icons.history)), SystemMouseCursors.click);
    expect(await cursorOver(find.text('On')), SystemMouseCursors.click);
    expect(await cursorOver(find.byIcon(Icons.copy)), SystemMouseCursors.click);
    expect(await cursorOver(find.text('Ink')), SystemMouseCursors.click);
    expect(await cursorOver(find.byType(Switch)), SystemMouseCursors.click);
    expect(await cursorOver(find.text('Off')), SystemMouseCursors.basic);
    expect(await cursorOver(find.text('Plain')), SystemMouseCursors.basic);
    expect(await cursorOver(find.byType(TextField)), SystemMouseCursors.text);
  });
}
