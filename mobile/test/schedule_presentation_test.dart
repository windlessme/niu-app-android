import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/features/schedule/schedule_screen.dart';
import 'package:niu_mobile/features/schedule/schedule_presentation.dart';

void main() {
  SchedulePeriod period(
    String label, {
    String course = '老師\n資料結構\nA101',
    String day = '星期一',
  }) => SchedulePeriod(label, '10:10–11:00', {day: course});
  test('parses school teacher/name/room and merges 3–4 and 6–8', () {
    final lessons = scheduleLessons(
      ClassSchedule(
        ['星期一'],
        [
          for (final n in [3, 4, 6, 7, 8]) period('$n'),
        ],
      ),
      '星期一',
      mergeConsecutive: true,
    );
    expect(lessons.length, 2);
    expect(lessons.first.name, '資料結構');
    expect(lessons.first.teacher, '老師');
    expect(lessons.first.room, 'A101');
    expect(lessons.first.periods, ['3', '4']);
    expect(lessons.last.periods, ['6', '7', '8']);
  });
  test('allows clock breaks between consecutive periods', () {
    final lessons = scheduleLessons(
      const ClassSchedule(
        ['星期一'],
        [
          SchedulePeriod('3', '10:10–11:00', {'星期一': '老師\n課程\nA101'}),
          SchedulePeriod('4', '11:10–12:00', {'星期一': '老師\n課程\nA101'}),
        ],
      ),
      '星期一',
      mergeConsecutive: true,
    );
    expect(lessons.single.start, '10:10');
    expect(lessons.single.end, '12:00');
  });
  test(
    'does not merge gaps, changed teachers/rooms, or different day/date keys',
    () {
      final schedule = ClassSchedule(
        ['星期一'],
        [
          period('1'),
          period('2', course: '另一位老師\n資料結構\nA101'),
          period('3', course: '另一位老師\n資料結構\nB202'),
          period('4', day: '星期二'),
          period('5'),
          period('6', day: '2026-09-28'),
          period('7', day: '2026-10-05'),
          period('8'),
          period('10'),
        ],
      );
      expect(
        scheduleLessons(schedule, '星期一', mergeConsecutive: true).length,
        6,
      );
      expect(scheduleLessons(schedule, '2026-09-28').single.periods, ['6']);
      expect(scheduleLessons(schedule, '2026-10-05').single.periods, ['7']);
    },
  );
  test('blank rows and unrecognized period labels break merging', () {
    final schedule = ClassSchedule(
      ['星期一'],
      [
        period('1'),
        const SchedulePeriod('2', '', {}),
        period('3'),
        period('午休'),
        period('4'),
      ],
    );
    expect(scheduleLessons(schedule, '星期一', mergeConsecutive: true).length, 4);
  });
  test('display defaults to individual periods even for identical courses', () {
    final result = scheduleLessons(
      ClassSchedule(['星期一'], [period('第三節'), period('第四節')]),
      '星期一',
    );
    expect(result.length, 2);
    expect(result.map((lesson) => lesson.periodLabel), ['第 三 節', '第 四 節']);
  });
}
