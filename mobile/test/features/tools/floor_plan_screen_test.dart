import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/features/tools/floor_plan_screen.dart';
import 'package:niu_mobile/shared/shared.dart';

Widget _app(Widget child) => MaterialApp(theme: NiuTheme.light, home: child);

void main() {
  testWidgets('opens on the building and floor of a timetable room', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const FloorPlanScreen(room: '綜303')));
    await tester.pumpAndSettle();
    expect(find.text('綜合教學大樓 3 樓'), findsOneWidget);
    expect(find.text('教師休息室'), findsOneWidget);
    expect(find.byIcon(Icons.place_rounded), findsOneWidget);
  });

  testWidgets('switching building resets floor and mark', (tester) async {
    await tester.pumpWidget(_app(const FloorPlanScreen(room: '綜303')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('教穡大樓'));
    await tester.pumpAndSettle();
    expect(find.text('教穡大樓 1 樓'), findsOneWidget);
    expect(find.byIcon(Icons.place_rounded), findsNothing);

    await tester.tap(find.text('B1'));
    await tester.pumpAndSettle();
    expect(find.text('教穡大樓 地下 1 樓'), findsOneWidget);
  });

  testWidgets('tapping a room in the list marks it', (tester) async {
    await tester.pumpWidget(_app(const FloorPlanScreen()));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('學生休息室'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('學生休息室'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.place_rounded), findsOneWidget);
  });
}
