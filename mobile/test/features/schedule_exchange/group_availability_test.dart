import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/features/schedule/schedule_models.dart';
import 'package:niu_mobile/features/schedule_exchange/group_availability.dart';
import 'package:niu_mobile/features/schedule_exchange/schedule_share.dart';

const header = ['節次', '時間', '星期一', '星期二', '星期三', '星期四', '星期五'];
const times = ['08:10~09:00', '09:10~10:00', '10:10~11:00'];

/// A table with [busy] courses keyed `mondayBasedDay * 100 + row`.
ScheduleSharePayload table(String name, Map<int, String> busy) =>
    ScheduleSharePayload.fromSchedule(
      ClassSchedule.fromRows([
        header,
        for (final (row, time) in times.indexed)
          [
            '${row + 1}',
            time,
            for (var d = 0; d < 5; d++) busy[d * 100 + row] ?? '',
          ],
      ]),
      shareId: ScheduleSharePayload.newShareId(),
      term: ScheduleShareTerm.containing(DateTime.now()),
      nickname: name,
      createdAt: DateTime.now(),
    );

void main() {
  final me = table('我', {0: '微積分', 402: '英文'});
  final an = table('小安', {100: '經濟學', 1: '經濟學'});

  test('counts who is free each period and names what the others have', () {
    final group = GroupAvailability(me, [me, an], ['我', '小安']);
    expect(group.rows, [0, 1, 2]);
    expect(group.free[0], [1]);
    expect(group.countAt(200), 2);
    expect(group.busyReason(0, 0), '微積分');
    expect(group.busyReason(1, 100), '經濟學');
    expect(group.common, contains(200));
    expect(group.common, isNot(contains(0)));
  });

  test('with no period free for all, lists where the most are free', () {
    final full = table('阿哲', {
      for (var d = 0; d < 5; d++)
        for (var r = 0; r < 3; r++) d * 100 + r: '實驗',
    });
    final group = GroupAvailability(me, [me, an, full], ['我', '小安', '阿哲']);
    expect(group.common, isEmpty);
    final best = group.mostFree;
    expect(best, contains(2));
    expect(best.every((k) => group.countAt(k) == 2), isTrue);
    final runs = group.runs(best);
    expect(runs.first.line, '週一・第 3 節・10:10–11:00');
    expect(runs.first.free, [0, 1]);
    // Tuesday 2–3 joins into one run; Wednesday is free for both all day.
    expect(runs.map((r) => r.line), contains('週二・第 2–3 節・9:10–11:00'));
    expect(runs.map((r) => r.line), contains('週三・第 1–3 節・8:10–11:00'));
  });

  test('nobody else free leaves no best times', () {
    final full = table('阿哲', {
      for (var d = 0; d < 5; d++)
        for (var r = 0; r < 3; r++) d * 100 + r: '實驗',
    });
    final group = GroupAvailability(full, [full, full], ['我', '阿哲']);
    expect(group.common, isEmpty);
    expect(group.mostFree, isEmpty);
  });
}
