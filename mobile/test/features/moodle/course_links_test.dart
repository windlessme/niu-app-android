import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/features/home/home_screen.dart';
import 'package:niu_mobile/features/schedule/schedule_screen.dart';
import 'package:niu_mobile/features/schedule/schedule_models.dart';

void main() {
  testWidgets('tapping today\'s course opens it in M 園區', (tester) async {
    final opened = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: CampusHomeScreen(
          name: '測試同學',
          courses: const [
            HomeCourse(name: '資料結構', time: '08:10~09:00', current: true),
          ],
          onOpenCourse: opened.add,
        ),
      ),
    );
    await tester.tap(find.text('資料結構'));
    await tester.pump();
    expect(opened, ['資料結構']);
  });

  testWidgets('tapping a lesson in the timetable opens it in M 園區', (
    tester,
  ) async {
    final opened = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScheduleView(
            schedule: ClassSchedule.fromRows([
              ['節次', '時間', '星期一'],
              ['1', '08:10~09:00', '陳老師\n資料結構\nA101'],
            ]),
            initialWeekday: 1,
            onOpenCourse: opened.add,
          ),
        ),
      ),
    );
    await tester.tap(find.text('資料結構'));
    await tester.pump();
    expect(opened, ['資料結構']);
  });
}
