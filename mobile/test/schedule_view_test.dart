import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/features/schedule/schedule_screen.dart';

void main() {
  testWidgets(
    'parsed school schedule fills bounded content after WebView handoff',
    (tester) async {
      final schedule = ClassSchedule.fromRows([
        ['節次', '時間', '星期一', '星期二', '星期三', '星期四', '星期五'],
        [
          '1',
          '08:10~09:00',
          '老師\n課程一\nA101',
          '老師\n課程二\nA102',
          '老師\n課程三\nA103',
          '老師\n課程四\nA104',
          '老師\n課程五\nA105',
        ],
      ]);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox.expand(
              child: ScheduleView(schedule: schedule, initialWeekday: 1),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TabBar), findsNothing);
      expect(find.textContaining('08:10'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets('320 wide, double text, $brightness has no overflow', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final schedule = ClassSchedule(
        ['星期一'],
        [
          const SchedulePeriod('3', '10:10–11:00', {
            '星期一': '王老師\n很長的課程名稱資料結構與演算法\n綜合教學大樓 A101',
          }),
          const SchedulePeriod('4', '11:10–12:00', {
            '星期一': '王老師\n很長的課程名稱資料結構與演算法\n綜合教學大樓 A101',
          }),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: ScheduleView(schedule: schedule, initialWeekday: 1),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('第 3 節'), findsOneWidget);
      expect(find.text('第 3–4 節'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(-800, 0),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('星期日'));
      await tester.pumpAndSettle();
      expect(find.text('沒有安排課程'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
