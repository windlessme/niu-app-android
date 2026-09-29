import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/core/platform/schedule_gateway.dart';
import 'package:niu_mobile/core/platform/schedule_ics.dart';

void main() {
  ScheduleSnapshot sample({
    String start = '2026-09-16',
    String end = '2027-01-15',
    int weekday = 1,
    int minute = 490,
    String title = '微積分',
  }) => ScheduleSnapshot(
    semesterStart: start,
    semesterEnd: end,
    blocks: [
      ScheduleBlock(
        id: 'math-1',
        title: title,
        weekday: weekday,
        startMinute: minute,
        endMinute: minute + 100,
        room: 'A,101;東\\側',
        teacher: '老師\r\n第二行',
      ),
    ],
  );
  String export(ScheduleSnapshot s) =>
      exportScheduleIcs(s, generatedAt: DateTime.utc(2026, 9, 1));
  String unfold(String value) => value.replaceAll('\r\n ', '');

  test(
    'first occurrence follows actual midweek semester start; end is inclusive',
    () {
      final ics = unfold(export(sample()));
      expect(ics, contains('DTSTART:20260921T001000Z\r\n'));
      expect(ics, contains('DTEND:20260921T015000Z\r\n'));
      expect(ics, contains('RRULE:FREQ=WEEKLY;UNTIL=20270115T155959Z'));
      expect(ics, isNot(contains('COUNT=18')));
    },
  );
  test('Taipei early civil times roll to the previous UTC day', () {
    final ics = unfold(export(sample(weekday: 3, minute: 10)));
    expect(ics, contains('DTSTART:20260915T161000Z'));
  });
  test('short semester omits weekdays outside the range', () {
    expect(export(sample(end: '2026-09-18')), isNot(contains('BEGIN:VEVENT')));
    expect(
      export(sample(end: '2026-09-16', weekday: 3)),
      contains('BEGIN:VEVENT'),
    );
  });
  test('escapes RFC text and folds Unicode on UTF-8 boundaries', () {
    final ics = export(sample(title: '中文課程' * 40));
    expect(unfold(ics), contains(r'LOCATION:A\,101\;東\\側'));
    expect(unfold(ics), contains(r'DESCRIPTION:老師\n第二行'));
    expect(unfold(ics), contains('SUMMARY:${'中文課程' * 40}'));
    for (final line in ics.split('\r\n')) {
      expect(utf8.encode(line).length, lessThanOrEqualTo(75));
      expect(line, isNot(contains('\uFFFD')));
    }
  });
  test('rejects normalized invalid dates and invalid block times', () {
    expect(() => export(sample(start: '2026-02-30')), throwsArgumentError);
    expect(() => export(sample(end: '2026-09-01')), throwsArgumentError);
    expect(() => export(sample(minute: 1400)), throwsArgumentError);
    expect(() => export(sample(weekday: 8)), throwsArgumentError);
  });
  test('UID is stable across export dates', () {
    final s = sample();
    String uid(String ics) =>
        unfold(ics).split('\r\n').firstWhere((l) => l.startsWith('UID:'));
    expect(
      uid(export(s)),
      uid(exportScheduleIcs(s, generatedAt: DateTime.utc(2027))),
    );
  });
}
