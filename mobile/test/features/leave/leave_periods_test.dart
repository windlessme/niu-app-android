import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/features/leave/leave_application_data.dart';
import 'package:niu_mobile/features/leave/leave_widgets.dart';
import 'package:niu_mobile/shared/shared.dart';

void main() {
  test('period numbers and times come out of the school labels', () {
    expect(leavePeriodNumber('3'), 3);
    expect(leavePeriodNumber('第3節'), 3);
    expect(leavePeriodNumber('第 10 節'), 10);
    expect(leavePeriodNumber('3 08:10~09:00'), 3);
    expect(leavePeriodNumber('08:10~09:00'), isNull);
    expect(leavePeriodNumber('午休'), isNull);
    expect(leavePeriodTime('3 08:10~09:00'), '08:10–09:00');
    expect(leavePeriodLabel(['3', '4']), '第 3–4 節');
    expect(leavePeriodLabel(['第5節']), '第 5 節');
    expect(leavePeriodLabel(['午休']), '午休');
  });

  test('tables are read by header, and by cell shape without one', () {
    final byHeader = leavePeriodEntries([
      ['請假日期', '請假節次', '課程名稱', '課號', '授課教師'],
      ['1151008', '3', '資料結構', 'B3E0101A', '王大明'],
    ]);
    expect(byHeader.single.date, '115/10/08');
    expect(byHeader.single.course, '資料結構');
    expect(byHeader.single.teacher, '王大明');
    final headers = leavePeriodEntries(
      [
        ['115/10/08', '4', '資料結構', 'B3E0101A', '王大明'],
      ],
      headers: ['請假日期', '請假節次', '課程名稱', '課號', '授課教師'],
    );
    expect(headers.single.number, 4);
    final shaped = leavePeriodEntries([
      ['115/09/30', '第5節', '計算機組織'],
    ]);
    expect(shaped.single.period, '第5節');
    expect(shaped.single.course, '計算機組織');
  });

  test('a record reads as day and period range', () {
    expect(
      leaveRecordPeriodSummary({
        '請假起日': '115/10/08',
        '請假訖日': '115/10/08',
        '起始節次': '3',
        '迄止節次': '4',
      }),
      '10/8（四）・第 3–4 節',
    );
    expect(
      leaveRecordPeriodSummary({
        '請假起日': '115/10/08',
        '請假訖日': '115/10/09',
        '起始節次': '3',
        '迄止節次': '2',
      }),
      '10/8（四）第 3 節 – 10/9（五）第 2 節',
    );
  });

  testWidgets('consecutive periods of one course share a block', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: NiuTheme.light,
        home: const Scaffold(
          body: LeavePeriodSchedule(
            entries: [
              LeavePeriodEntry(
                date: '115/10/08',
                period: '3',
                course: '資料結構',
                teacher: '王大明',
              ),
              LeavePeriodEntry(
                date: '115/10/08',
                period: '4',
                course: '資料結構',
                teacher: '王大明',
              ),
              LeavePeriodEntry(date: '115/10/08', period: '6', course: '英文'),
              LeavePeriodEntry(date: '115/10/09', period: '1', course: '英文'),
            ],
          ),
        ),
      ),
    );
    expect(find.text('10/8（四）'), findsOneWidget);
    expect(find.text('3 節'), findsOneWidget);
    expect(find.text('第 3–4 節'), findsOneWidget);
    expect(find.text('資料結構'), findsOneWidget);
    expect(find.text('第 6 節'), findsOneWidget);
    expect(find.text('10/9（五）'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
