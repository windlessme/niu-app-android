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
    expect(find.text('暫時無法更新，目前顯示上次資料。'), findsOneWidget);
    expect(find.text('今天接下來沒有課程，好好安排你的時間。'), findsOneWidget);
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
      expect(
        find.text(
          hasSchedule ? '今天接下來沒有課程，好好安排你的時間。' : '尚未同步課表，開啟完整課表即可取得今日安排。',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }
  });
}
