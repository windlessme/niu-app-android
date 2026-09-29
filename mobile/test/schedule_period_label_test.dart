import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/features/schedule/schedule_presentation.dart';
import 'package:niu_mobile/features/schedule/schedule_screen.dart';

void main() {
  ScheduleLesson lesson(List<String> periods) => ScheduleLesson(
    day: '星期二',
    name: '英文',
    teacher: '教師',
    room: 'A101',
    periods: periods,
    start: '10:10',
    end: '12:00',
  );
  test('period wrappers are applied once for school formats', () {
    for (final label in ['2', '第2節', '第 2 節']) {
      expect(lesson([label]).periodLabel, '第 2 節');
    }
    expect(lesson(['第二節']).periodLabel, '第 二 節');
    expect(lesson(['第 A 節']).periodLabel, '第 A 節');
    expect(lesson(['第三節', '第四節']).periodLabel, '第 三–四 節');
    expect(lesson([]).periodLabel, '節次未提供');
  });
  test('Chinese consecutive periods merge and gaps stay separate', () {
    final schedule = ClassSchedule(
      ['星期二'],
      [
        for (final label in ['第九節', '第十節', '第十一節', '第十三節'])
          SchedulePeriod(label, '10:10~11:00', {'星期二': '教師\n英文\nA101'}),
      ],
    );
    final blocks = scheduleLessons(schedule, '星期二', mergeConsecutive: true);
    expect(blocks.length, 2);
    expect(blocks.first.periodLabel, '第 九–十一 節');
    expect(blocks.last.periodLabel, '第 十三 節');
  });
}
