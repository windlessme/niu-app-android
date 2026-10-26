import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/features/schedule/custom_courses.dart';
import 'package:niu_mobile/features/schedule/schedule_models.dart';
import 'package:niu_mobile/features/schedule/schedule_presentation.dart';
import 'package:niu_mobile/features/schedule_exchange/schedule_share.dart';

/// Taipei Fri 2026-10-23 10:00, as in the iOS checks.
final now = DateTime.utc(2026, 10, 23, 2);
const id = '6F1C2E0B-6E57-4D6A-9E0F-0B9E3C1D2A4B';
const term = ScheduleShareTerm(115, 1);

/// The iOS checks' hand-built wire, compressed as Apple's COMPRESSION_ZLIB
/// does (raw DEFLATE, no header).
const iosCode =
    'NIUTT1:HYw9CsJAEIXv8upZmFl3N266_GwuISlEGxsRFImIrdiorVewEU_gbaLXcBLmh3mP780Re-RCWCFHaKSyiUsTks-Mq0NhYuLGcBnTpJLaFq4E4aAB8YTtGNzpzqLNLE-ZCWv907_v38dNySXyGZO0hI1eELUsVM1VucjknY5nCszqLgam_7x-z2t_OQ9cN-aHMqLdnv4';

const wire =
    '{"v":1,"i":"$id","y":115,"s":1,"t":1792720800,"n":"小明","d":[0,1],"p":["1","2"],"a":[490,540,550,600],"c":["微積分"],"x":[0,0,0,-1,-1]}';

/// Builds a code from raw JSON, skipping the encoder's own cleaning.
String code(String json) =>
    ScheduleSharePayload.prefix +
    base64Url
        .encode(ZLibEncoder(raw: true).convert(utf8.encode(json)))
        .replaceAll('=', '');

ScheduleShareError? error(String text) {
  try {
    ScheduleSharePayload.decode(text, now: now);
    return null;
  } on ScheduleShareError catch (e) {
    return e;
  }
}

ClassSchedule table(
  String? Function(int row, int day) fill,
) => ClassSchedule.fromRows([
  ['節次', '時間', '星期一', '星期二', '星期三', '星期四', '星期五'],
  for (var row = 1; row <= 10; row++)
    [
      '$row',
      '${(row + 7).toString().padLeft(2, '0')}:10~${(row + 8).toString().padLeft(2, '0')}:00',
      for (var day = 0; day < 5; day++) fill(row, day) ?? '',
    ],
]);

ScheduleSharePayload share(
  ClassSchedule schedule, {
  bool rooms = false,
  bool teachers = false,
  String nickname = '小明',
}) => ScheduleSharePayload.fromSchedule(
  schedule,
  shareId: id,
  term: term,
  nickname: nickname,
  createdAt: now,
  includeRooms: rooms,
  includeTeachers: teachers,
);

void main() {
  test('Asia/Taipei semester boundaries', () {
    expect(ScheduleShareTerm.containing(now), term);
    expect(
      ScheduleShareTerm.containing(DateTime.utc(2027, 1, 31, 15, 59)),
      term,
    );
    expect(
      ScheduleShareTerm.containing(DateTime.utc(2027, 1, 31, 16)),
      const ScheduleShareTerm(115, 2),
    );
    expect(
      ScheduleShareTerm.containing(DateTime.utc(2026, 7, 31, 16)),
      term,
      reason: 'Taipei 8/1 starts the new academic year',
    );
    expect(term.endDate, DateTime.utc(2027, 1, 31, 16));
    expect(term.next.endDate, DateTime.utc(2027, 7, 31, 16));
    expect(term.title, '115 學年度第 1 學期');
  });

  test('reads a code made on iOS', () {
    final payload = ScheduleSharePayload.decode(iosCode, now: now);
    expect(payload.nickname, '小明');
    expect(payload.shareId, id);
    expect(payload.term, term);
    expect(payload.days, [0, 1]);
    expect(payload.periods, [
      const SharePeriod('1', 490, 540),
      const SharePeriod('2', 550, 600),
    ]);
    expect(payload.names, ['微積分']);
    expect(payload.slots, [const ShareSlot(0, 0, 0)]);
  });

  test('writes what iOS reads: sorted short keys, raw DEFLATE, no padding', () {
    final payload = share(
      table((row, day) => row == 1 && day == 0 ? '王老師\n微積分\nA101' : null),
      rooms: true,
    );
    final text = payload.encoded();
    expect(text, startsWith('NIUTT1:'));
    expect(text, isNot(contains('=')));
    final body = base64Url.decode(base64Url.normalize(text.substring(7)));
    final json = utf8.decode(ZLibDecoder(raw: true).convert(body));
    expect(json, startsWith('{"a":[490,540,'));
    final keys = (jsonDecode(json) as Map).keys.toList();
    expect(keys, [...keys]..sort());
    expect(jsonDecode(json), containsPair('r', ['A101']));
    expect((jsonDecode(json) as Map).containsKey('e'), isFalse);
    expect(text, payload.encoded(), reason: 'same table, same code');
  });

  test('size budget and round trip', () {
    final busy = table((row, day) {
      final n = (row * 5 + day) % 40;
      return '授課教師${n % 25}\n跨領域人工智慧應用專題實作（二）第$n組\n綜合大樓${n % 20}樓教室';
    });
    final minimal = share(busy);
    final text = minimal.encoded();
    expect(text.length, lessThanOrEqualTo(1800));
    final back = ScheduleSharePayload.decode(text, now: now);
    expect(back.slots, minimal.slots);
    expect(back.names, minimal.names);
    expect(minimal.rooms, isEmpty);
    expect(minimal.teachers, isEmpty);
    expect(minimal.days, [0, 1, 2, 3, 4]);
    expect(text, isNot(contains('授課')));

    final typical = share(
      table(
        (row, day) =>
            row % 3 == 0 ? null : '教師\n課程$day-${row ~/ 3}\nE${day}0$row',
      ),
      rooms: true,
      teachers: true,
    );
    final round = ScheduleSharePayload.decode(typical.encoded(), now: now);
    expect(round.rooms, typical.rooms);
    expect(round.teachers, typical.teachers);
    expect(round.slots, typical.slots);
  });

  test('custom courses stay out unless comparing on this device', () {
    final school = table((row, day) => row == 1 && day == 0 ? '資料結構' : null);
    final shown = school.withCustomCourses([
      const CustomCourse(
        id: 'c1',
        name: '打工',
        weekdays: [1],
        startPeriod: '3',
        endPeriod: '3',
        lastDay: '2099-12-31',
      ),
    ], DateTime(2026, 10, 23));
    expect(share(shown).slots, hasLength(1));
    final mine = ScheduleSharePayload.fromSchedule(
      shown,
      shareId: id,
      term: term,
      nickname: '我',
      createdAt: now,
      withCustom: true,
    );
    expect(mine.slots, hasLength(2));
    expect(mine.names, ['資料結構', '打工']);
  });

  test('text cleaning matches iOS', () {
    expect(ScheduleSharePayload.clean('\u202E微積分\u0000\n(一)'), '微積分 (一)');
    expect(ScheduleSharePayload.cleanNickname('長' * 40).runes.length, 20);
    expect(
      utf8.encode(ScheduleSharePayload.clean('字' * 40)).length,
      lessThanOrEqualTo(64),
    );
    expect(ScheduleSharePayload.cleanNickname('👨‍👩‍👧 小明'), '👨‍👩‍👧 小明');
    expect(ScheduleSharePayload.clean('  a　 b  '), 'a b');
  });

  test('hostile and stale codes are rejected', () {
    expect(ScheduleSharePayload.decode(code(wire), now: now).nickname, '小明');
    expect(error('https://example.com'), ScheduleShareError.notScheduleCode);
    expect(error('NIUTT2:abc'), ScheduleShareError.unsupportedVersion);
    expect(error('NIUTT1:!!!'), ScheduleShareError.malformed);
    expect(error('A' * 5000), ScheduleShareError.tooLarge);
    expect(
      error(code(wire.replaceFirst('"v":1', '"v":2'))),
      ScheduleShareError.unsupportedVersion,
    );
    for (final (from, to) in [
      ('小明', '\u202E小明'),
      ('"x":[0,0,0,-1,-1]', '"x":[0,5,0,-1,-1]'),
      ('"x":[0,0,0,-1,-1]', '"x":[0,0,0,-1,-1,0,0,0,-1,-1]'),
      ('"x":[0,0,0,-1,-1]', '"x":[3,0,0,-1,-1]'),
      ('"x":[0,0,0,-1,-1]', '"x":[0,0,0,0,-1]'),
      ('"a":[490,540,550,600]', '"a":[540,490,550,600]'),
      ('"a":[490,540,550,600]', '"a":[490,540]'),
      ('"d":[0,1]', '"d":[0,0]'),
      ('"s":1', '"s":3'),
      ('"i":"$id"', '"i":"nope"'),
      ('"c":["微積分"]', '"c":[""]'),
      ('"c":["微積分"]', '"c":["微積分 "]'),
      ('"n":"小明"', '"n":5'),
    ]) {
      expect(error(code(wire.replaceFirst(from, to))), isNotNull, reason: to);
    }
    expect(
      error(code(wire.replaceFirst('"x":[0,0,0,-1,-1]', '"x":[]'))),
      ScheduleShareError.empty,
    );
    expect(
      error(code(wire.replaceFirst('1792720800', '${1792720800 - 86401}'))),
      ScheduleShareError.expiredCode,
    );
    expect(
      error(code(wire.replaceFirst('1792720800', '${1792720800 + 301}'))),
      ScheduleShareError.futureCode,
    );
    expect(
      ScheduleSharePayload.decode(
        code(wire.replaceFirst('1792720800', '${1792720800 + 299}')),
        now: now,
      ).nickname,
      '小明',
      reason: 'five minutes of clock skew allowed',
    );
    final ended = wire
        .replaceFirst('"y":115', '"y":114')
        .replaceFirst('"s":1', '"s":2');
    expect(error(code(ended)), ScheduleShareError.termEnded);

    // A decompression bomb: tiny input, more than 32 KB once inflated.
    final bomb = '{"v":1,"n":"${'a' * 40000}"}';
    expect(error(code(bomb)), ScheduleShareError.malformed);
  });

  test('a classmate table renders like the school one', () {
    final payload = share(
      table((row, day) => row == 2 && day == 1 ? '王老師\n微積分\nA101' : null),
      rooms: true,
    );
    final schedule = payload.toClassSchedule();
    final lessons = scheduleLessons(schedule, '星期二');
    expect(lessons.single.name, '微積分');
    expect(lessons.single.room, 'A101');
    expect(lessons.single.teacher, '', reason: 'teacher not shared');
    expect(lessons.single.start, '09:10');
  });

  group('common free periods', () {
    ScheduleSharePayload from(String json) =>
        ScheduleSharePayload.fromWire(jsonDecode(json) as Map<String, dynamic>);
    String wireWith({
      List<int> days = const [0, 1],
      String periods = '"p":["1","2","3"],"a":[490,540,550,600,610,660]',
      String slots = '"x":[0,0,0,-1,-1]',
    }) =>
        '{"v":1,"i":"$id","y":115,"s":1,"t":1792720800,"n":"x","d":$days,$periods,"c":["課"],$slots}';

    test('free only where nobody has class and every table covers it', () {
      final me = from(wireWith());
      final friend = from(wireWith(slots: '"x":[1,1,0,-1,-1]'));
      expect(me.freeSlots([friend]), {
        0 * 100 + 1,
        0 * 100 + 2,
        1 * 100 + 0,
        1 * 100 + 2,
      });
      final partTime = from(wireWith(days: [0], slots: '"x":[0,2,0,-1,-1]'));
      expect(me.freeSlots([friend, partTime]), {
        1,
      }, reason: 'Tuesday is unknown for a table without Tuesday');
    });

    test('compares minutes, not period numbers', () {
      final me = from(wireWith(slots: '"x":[]'));
      // Their only period spans my first two.
      final other = from(
        wireWith(
          periods: '"p":["A"],"a":[500,560]',
          slots: '"x":[0,0,0,-1,-1]',
        ),
      );
      expect(me.freeSlots([other]), isEmpty, reason: 'covers 9:20–11:00 only');
      final wide = from(
        wireWith(
          periods: '"p":["A","B"],"a":[480,560,570,700]',
          slots: '"x":[0,0,0,-1,-1]',
        ),
      );
      expect(me.freeSlots([wide]), {2, 100, 101, 102});
    });

    test('breaks of up to 20 minutes count as covered', () {
      final me = from(wireWith(periods: '"p":["1"],"a":[540,600]'));
      final gap = from(
        wireWith(
          periods: '"p":["1","2"],"a":[480,530,550,620]',
          slots: '"x":[]',
        ),
      );
      expect(gap.covers(0, 540, 600), isTrue);
      final wideGap = from(
        wireWith(
          periods: '"p":["1","2"],"a":[480,520,550,620]',
          slots: '"x":[]',
        ),
      );
      expect(wideGap.covers(0, 540, 600), isFalse);
      expect(me.covers(2, 540, 600), isFalse);
    });
  });
}
