import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/features/home/home_screen.dart';
import 'package:niu_mobile/shared/shared.dart';

void main() {
  testWidgets('failed home refresh retains content and reports recovery', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: NiuTheme.light,
        home: CampusHomeScreen(
          name: '測試同學',
          hasSchedule: true,
          onRefresh: () async => throw StateError('fixture failure'),
        ),
      ),
    );
    final refresh = tester.widget<RefreshIndicator>(
      find.byType(RefreshIndicator),
    );
    await refresh.onRefresh();
    await tester.pump();
    expect(find.text('更新失敗，先顯示上次的資料'), findsOneWidget);
    expect(find.text('今天沒有接下來的課'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('home distinguishes not-synced schedule from completed day', (
    tester,
  ) async {
    for (final hasSchedule in [false, true]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: NiuTheme.dark,
          home: CampusHomeScreen(name: '測試同學', hasSchedule: hasSchedule),
        ),
      );
      expect(find.text(hasSchedule ? '今天沒有接下來的課' : '還沒有課表'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}
