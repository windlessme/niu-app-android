import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/features/schedule/custom_course_editor.dart';
import 'package:niu_mobile/features/schedule/custom_courses.dart';
import 'package:niu_mobile/features/schedule/schedule_export.dart';
import 'package:niu_mobile/features/schedule/schedule_models.dart';
import 'package:niu_mobile/features/schedule/schedule_presentation.dart';
import 'package:niu_mobile/features/schedule/schedule_wallpaper.dart';
import 'package:niu_mobile/shared/shared.dart';
import 'package:shared_preferences/shared_preferences.dart';

final school = ClassSchedule.fromRows([
  ['節次', '時間', '星期一', '星期二', '星期三', '星期四', '星期五'],
  ['1', '08:10~09:00', '王老師\n資料結構\nA101', '', '', '', ''],
  ['2', '09:10~10:00', '王老師\n資料結構\nA101', '', '', '', ''],
  ['3', '10:10~11:00', '', '', '', '', ''],
]);

CustomCourse course({
  String id = 'c1',
  List<int> weekdays = const [0],
  String start = '3',
  String end = '3',
  String lastDay = '2026-12-31',
}) => CustomCourse(
  id: id,
  name: '日文社',
  classroom: '社辦',
  weekdays: weekdays,
  startPeriod: start,
  endPeriod: end,
  lastDay: lastDay,
);

final monday = DateTime(2026, 10, 5);

void main() {
  test('custom courses fill empty slots of the week, never school ones', () {
    final merged = school.withCustomCourses([
      course(),
      course(id: 'c2', start: '1', end: '2'), // Taken by 資料結構.
      course(id: 'c3', weekdays: [5]), // Saturday: a new day column.
    ], monday);
    final lessons = scheduleLessons(merged, '星期一');
    expect([for (final l in lessons) l.name], ['資料結構', '資料結構', '日文社']);
    expect(lessons.last.customId, 'c1');
    expect(lessons.last.room, '社辦');
    expect(merged.days, contains('星期六'));
    expect(scheduleLessons(merged, '星期六').single.customId, 'c3');
    // The cache stays the school's.
    expect(school.periods[2].custom, isEmpty);
  });

  test('a course shows through its last day only', () {
    final last = course(lastDay: '2026-10-05');
    expect(
      scheduleLessons(
        school.withCustomCourses([last], monday),
        '星期一',
      ).last.customId,
      'c1',
      reason: 'Monday 10/5 is its last day',
    );
    final expired = course(lastDay: '2026-10-04');
    expect(school.withCustomCourses([expired], monday), same(school));
  });

  test('conflicts name the course already there', () {
    expect(
      school.conflict(course(start: '1', end: '1'), const [], monday),
      contains('資料結構'),
    );
    expect(
      school.conflict(course(id: 'new'), [course()], monday),
      contains('自訂課程「日文社」'),
    );
    expect(school.conflict(course(), [course()], monday), isNull);
  });

  test('widgets and reminders get custom courses with their own fields', () {
    final blocks = scheduleBlocks(school.withCustomCourses([course()], monday));
    final custom = blocks.where((b) => b.title == '日文社').single;
    expect(custom.room, '社辦');
    expect(custom.weekday, 1);
    // The device drops it after its last day, even if the app isn't opened.
    expect(custom.lastDay, '2026-12-31');
    expect(custom.toJson()['lastDay'], '2026-12-31');
    final schoolBlock = blocks.firstWhere((b) => b.title != '日文社');
    expect(schoolBlock.toJson().containsKey('lastDay'), isFalse);
  });

  test('each account keeps its own courses', () async {
    SharedPreferences.setMockInitialValues({});
    final store = CustomCourseStore.instance..reset();
    await store.save('b1', course());
    expect(store.coursesFor('b1').single.name, '日文社');
    expect(store.coursesFor('b2'), isEmpty);
    await store.load('b2');
    expect(store.coursesFor('b2'), isEmpty);
    await store.load('b1');
    expect(store.coursesFor('b1'), hasLength(1));
    await store.delete('b1', 'c1');
    expect(store.coursesFor('b1'), isEmpty);
  });

  testWidgets('the editor saves a course and refuses a taken slot', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final store = CustomCourseStore.instance..reset();
    await tester.pumpWidget(
      MaterialApp(
        theme: NiuTheme.light,
        home: CustomCourseEditorScreen(
          schedule: school,
          account: 'b1',
          weekday: 0,
          now: monday,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '課程名稱'), '日文社');
    await tester.pump();
    // Starts at the first morning period, taken by 資料結構 on Monday.
    expect(find.textContaining('已有「資料結構」'), findsOneWidget);
    await tester.tap(find.text('二'));
    await tester.tap(find.text('一'));
    await tester.pump();
    await tester.tap(find.text('儲存'));
    await tester.pumpAndSettle();
    expect(store.coursesFor('b1').single.weekdays, [1]);
  });

  test('the wallpaper shows the weekdays and only the periods in use', () {
    final content = WallpaperContent(
      school.withCustomCourses([
        course(weekdays: [2]),
      ], monday),
    );
    expect(content.days, [0, 1, 2, 3, 4]);
    expect(content.first, 0);
    expect(content.last, 2);
    expect(content.blocks, hasLength(2));
    expect(
      content.blocks.where((b) => b.lesson.customId != null).single.column,
      2,
    );
  });

  testWidgets('the wallpaper page renders the canvas', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.7;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: NiuTheme.light,
        home: ScheduleWallpaperScreen(
          schedule: school,
          withCustom: school.withCustomCourses([course()], monday),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ScheduleWallpaperCanvas), findsOneWidget);
    await tester.scrollUntilVisible(find.text('設為鎖定畫面桌布'), 300);
    expect(find.text('包含自訂課程'), findsOneWidget);
    expect(find.text('設為鎖定畫面桌布'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
