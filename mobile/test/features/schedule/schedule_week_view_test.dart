import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/features/schedule/schedule_models.dart';
import 'package:niu_mobile/features/schedule/schedule_screen.dart';
import 'package:niu_mobile/features/schedule/schedule_week_view.dart';
import 'package:niu_mobile/shared/shared.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _rows = [
  ['節次', '時間', '星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'],
  ['1', '08:10~09:00', '', '', '', '', '', '', ''],
  ['2', '09:10~10:00', '王大明\n資料結構\n工程館 E301', '', '', '', '', '', ''],
  [
    '3',
    '10:10~11:00',
    '王大明\n資料結構\n工程館 E301',
    '',
    '李小華\n線性代數\nA101',
    '',
    '',
    '',
    '',
  ],
  ['4', '11:10~12:00', '', '', '', '', '', '', ''],
  ['5', '13:10~14:00', '', '', '', '', 'Emily\n英文\nB202', '', ''],
  ['6', '14:10~15:00', '', '', '', '', '', '', ''],
];

Widget _app(Widget child, {double width = 390}) => MediaQuery(
  data: MediaQueryData(size: Size(width, 900)),
  child: MaterialApp(
    theme: NiuTheme.light,
    home: Scaffold(body: SingleChildScrollView(child: child)),
  ),
);

void main() {
  testWidgets('a week shows each course once across its periods', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      _app(
        ScheduleWeekView(
          schedule: ClassSchedule.fromRows(_rows),
          // Monday 2026-10-05, 09:30 in Taipei.
          now: DateTime(2026, 10, 5, 9, 30),
        ),
      ),
    );
    // Weekdays only: Saturday and Sunday have no class.
    for (final day in ['一', '二', '三', '四', '五']) {
      expect(find.text(day), findsOneWidget);
    }
    expect(find.text('六'), findsNothing);
    // Periods 2–5 are shown; the empty first and last periods are not.
    expect(find.text('1'), findsNothing);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    expect(find.text('6'), findsNothing);
    // 資料結構 spans periods 2–3 as a single, taller block.
    expect(find.text('資料結構'), findsOneWidget);
    final block = tester.getSize(find.bySemanticsLabel(RegExp('^資料結構')));
    final single = tester.getSize(find.bySemanticsLabel(RegExp('^線性代數')));
    expect(block.height, greaterThan(single.height * 1.8));
    expect(find.bySemanticsLabel(RegExp('資料結構.*上課中')), findsOneWidget);
    await tester.tap(find.text('英文'));
    await tester.pumpAndSettle();
    expect(find.text('星期五・第 5 節・13:10–14:00'), findsOneWidget);
    expect(find.text('B202'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 390.0]) {
    testWidgets('Saturday and Sunday classes fit without scrolling '
        '(width $width)', (tester) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final rows = [
        for (final r in _rows) [...r],
      ];
      rows[2][7] = '張老師\n服務學習\n操場';
      rows[3][8] = '林老師\n校外實習\n校外';
      await tester.pumpWidget(
        _app(
          ScheduleWeekView(
            schedule: ClassSchedule.fromRows(rows),
            now: DateTime(2026, 10, 10, 9, 30),
          ),
          width: width,
        ),
      );
      expect(find.text('六'), findsOneWidget);
      expect(find.text('日'), findsOneWidget);
      expect(find.text('服務學習'), findsOneWidget);
      // Every day fits the width; nothing scrolls sideways.
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is SingleChildScrollView &&
              w.scrollDirection == Axis.horizontal,
        ),
        findsNothing,
      );
      final sunday = tester.getRect(find.bySemanticsLabel(RegExp('^校外實習')));
      expect(sunday.right, lessThanOrEqualTo(width + 0.5));
      // Saturday 10/10 is today.
      expect(find.bySemanticsLabel(RegExp('^今天，星期六')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('days carry their dates and a line marks the time', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Future<void> at(DateTime now) => tester.pumpWidget(
      _app(ScheduleWeekView(schedule: ClassSchedule.fromRows(_rows), now: now)),
    );
    await at(DateTime(2026, 10, 7, 9, 35)); // Wednesday, in period 2.
    expect(find.text('10/5'), findsOneWidget); // Monday of that week.
    expect(find.text('10/9'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('^今天，星期三')), findsOneWidget);
    expect(find.bySemanticsLabel('現在時間'), findsOneWidget);
    final period2 = tester.getRect(find.text('2'));
    final period3 = tester.getRect(find.text('3'));
    final line = tester.getRect(find.bySemanticsLabel('現在時間'));
    expect(line.center.dy, greaterThan(period2.top));
    expect(line.center.dy, lessThan(period3.top));
    // Before the first shown period and after the last, no line.
    await at(DateTime(2026, 10, 7, 7, 0));
    expect(find.bySemanticsLabel('現在時間'), findsNothing);
    await at(DateTime(2026, 10, 7, 18, 0));
    expect(find.bySemanticsLabel('現在時間'), findsNothing);
  });

  testWidgets('rows grow to fill the height they are given', (tester) async {
    Future<double> rowFor(double height) async {
      await tester.pumpWidget(
        _app(
          ScheduleWeekView(
            schedule: ClassSchedule.fromRows(_rows),
            height: height,
          ),
        ),
      );
      return tester.getTopLeft(find.text('3')).dy -
          tester.getTopLeft(find.text('2')).dy;
    }

    final short = await rowFor(0);
    final tall = await rowFor(600);
    expect(tall, greaterThan(short));
    // Never so tall that four periods stop reading as a table.
    expect(tall, lessThanOrEqualTo(short * 1.6 + 0.5));
  });

  testWidgets('the schedule page remembers 整週', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      _app(
        ScheduleView(schedule: ClassSchedule.fromRows(_rows), embedded: true),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ScheduleWeekView), findsNothing);
    await tester.tap(find.text('整週'));
    await tester.pumpAndSettle();
    expect(find.byType(ScheduleWeekView), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('scheduleWeekView'), isTrue);
    // A new visit opens in the week view.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      _app(
        ScheduleView(schedule: ClassSchedule.fromRows(_rows), embedded: true),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ScheduleWeekView), findsOneWidget);
  });
}
