import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/features/lunch/lunch_picker.dart';
import 'package:niu_mobile/features/lunch/lunch_picker_screen.dart';
import 'package:niu_mobile/shared/shared.dart';

void main() {
  test('a redraw never repeats while there is a choice', () {
    final random = Random(1);
    for (var i = 0; i < 50; i++) {
      expect(pickLunch([1, 2, 3], avoiding: 2, random: random), isNot(2));
    }
    expect(pickLunch([7], avoiding: 7), 7);
    expect(pickLunch(<int>[]), isNull);
  });

  test('searches stay around the fixed spot, never the phone', () {
    final uri = LunchArea.campus.mapSearch('牛肉麵');
    expect(uri.scheme, 'geo');
    expect(uri.path, '24.7461,121.7475');
    expect(uri.queryParameters['q'], '牛肉麵');
    expect(
      LunchArea.station.webSearch('拉麵').queryParameters['query'],
      '拉麵 宜蘭火車站',
    );
    // Same lists as iOS: twelve dishes in each.
    for (final c in LunchCategory.values) {
      expect(c.dishes, hasLength(12), reason: c.title);
    }
  });

  Widget app(Widget child) => MaterialApp(theme: NiuTheme.light, home: child);

  // The wheel runs on timers, which pumpAndSettle doesn't wait for.
  Future<void> spin(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  testWidgets('draws a category and a dish, then opens the map', (
    tester,
  ) async {
    final opened = <Uri>[];
    await tester.pumpWidget(
      app(
        LunchPickerScreen(
          launch: (uri) async {
            opened.add(uri);
            return false; // no map app: fall back to the web
          },
        ),
      ),
    );
    expect(find.text('先決定吃麵、飯還是其他'), findsOneWidget);
    expect(find.textContaining('裡挑一道'), findsNothing);

    await tester.tap(find.text('隨機選類別'));
    await tester.pump();
    expect(find.text('抽籤中…'), findsOneWidget);
    await spin(tester);
    expect(find.text('重抽類別'), findsOneWidget);
    expect(find.text('還沒決定'), findsOneWidget);

    // Picking by hand works too, and keeps the step open.
    await tester.tap(find.text('飯'));
    await tester.pump();
    expect(find.text('從「飯」裡挑一道'), findsOneWidget);

    await tester.tap(find.text('抽一道飯'));
    await spin(tester);
    final dish = LunchCategory.rice.dishes.firstWhere(
      (d) => find.text('今天中午就吃$d吧！').evaluate().isNotEmpty,
    );
    await tester.scrollUntilVisible(find.text('在地圖搜尋宜蘭火車站的$dish'), 200);
    await tester.tap(find.text('在地圖搜尋宜蘭火車站的$dish'));
    await tester.pumpAndSettle();
    expect(opened.map((u) => u.scheme), ['geo', 'https']);
    expect(find.text('無法開啟地圖'), findsOneWidget);

    await tester.tap(find.text('重來'));
    await tester.pump();
    expect(find.text('隨機選類別'), findsOneWidget);
    expect(find.textContaining('裡挑一道'), findsNothing);
  });
}
