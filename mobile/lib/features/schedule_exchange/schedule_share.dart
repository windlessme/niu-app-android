import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:characters/characters.dart';

import '../schedule/schedule_models.dart';
import '../schedule/schedule_presentation.dart';

/// A school semester in Asia/Taipei: 第1學期 8/1–1/31, 第2學期 2/1–7/31.
class ScheduleShareTerm implements Comparable<ScheduleShareTerm> {
  const ScheduleShareTerm(this.academicYear, this.semester);

  factory ScheduleShareTerm.containing(DateTime instant) {
    final taipei = instant.toUtc().add(const Duration(hours: 8));
    final month = taipei.month;
    return ScheduleShareTerm(
      taipei.year - (month >= 8 ? 1911 : 1912),
      month >= 8 || month == 1 ? 1 : 2,
    );
  }

  final int academicYear;
  final int semester;

  String get title => '$academicYear 學年度第 $semester 學期';

  /// Taipei midnight of the next semester's first day (2/1 or 8/1).
  DateTime get endDate => DateTime.utc(
    academicYear + 1912,
    semester == 1 ? 2 : 8,
  ).subtract(const Duration(hours: 8));

  ScheduleShareTerm get next => semester == 1
      ? ScheduleShareTerm(academicYear, 2)
      : ScheduleShareTerm(academicYear + 1, 1);

  @override
  int compareTo(ScheduleShareTerm other) => academicYear != other.academicYear
      ? academicYear.compareTo(other.academicYear)
      : semester.compareTo(other.semester);

  @override
  bool operator ==(Object other) =>
      other is ScheduleShareTerm &&
      other.academicYear == academicYear &&
      other.semester == semester;

  @override
  int get hashCode => Object.hash(academicYear, semester);
}

enum ScheduleShareError implements Exception {
  notScheduleCode('這不是 NIU-Life 的課表 QR Code。'),
  unsupportedVersion('這個 QR Code 來自較新版本的 App，請先更新 App 再掃描。'),
  malformed('QR Code 內容不完整或格式錯誤，請對方重新產生。'),
  tooLarge('QR Code 內容超過可接受的大小。'),
  expiredCode('這個 QR Code 已超過 24 小時，請對方重新產生。'),
  futureCode('QR Code 的建立時間晚於這台裝置的時間，請確認裝置時間設定。'),
  termEnded('這份課表的學期已經結束。'),
  empty('這份課表沒有任何課程。');

  const ScheduleShareError(this.message);
  final String message;
}

class SharePeriod {
  const SharePeriod(this.id, this.start, this.end);
  final String id;

  /// Minutes after Taipei midnight.
  final int start, end;

  @override
  bool operator ==(Object other) =>
      other is SharePeriod &&
      other.id == id &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(id, start, end);
}

class ShareSlot {
  const ShareSlot(this.day, this.period, this.name, [this.room, this.teacher]);

  /// Monday-based: 0 = 星期一 … 6 = 星期日.
  final int day;
  final int period, name;
  final int? room, teacher;

  @override
  bool operator ==(Object other) =>
      other is ShareSlot &&
      other.day == day &&
      other.period == period &&
      other.name == name &&
      other.room == room &&
      other.teacher == teacher;

  @override
  int get hashCode => Object.hash(day, period, name, room, teacher);
}

/// Whitelisted data in a timetable QR code, the same `NIUTT1:` format the
/// iOS app reads and writes. Built field by field from the school table, so
/// sessions, custom courses and anything else never reach it.
class ScheduleSharePayload {
  ScheduleSharePayload({
    required this.shareId,
    required this.term,
    required this.createdAt,
    required this.nickname,
    required this.days,
    required this.periods,
    required this.names,
    required this.rooms,
    required this.teachers,
    required this.slots,
  });

  static const prefix = 'NIUTT1:';

  /// QR codes are readable by anyone nearby; this only stops old screenshots
  /// from circulating.
  static const validity = Duration(hours: 24);
  static const clockSkew = Duration(minutes: 5);

  /// Keeps the code scannable on a phone screen at error correction level M.
  static const maxEncodedLength = 1800;
  static const maxInputLength = 4096;
  static const maxDecompressedBytes = 32 * 1024;
  static const maxPeriods = 20;
  static const maxStrings = 80;
  static const maxSlots = 140;
  static const maxTextBytes = 64;
  static const maxNicknameLength = 20;

  final String shareId;
  final ScheduleShareTerm term;
  final DateTime createdAt;
  final String nickname;

  /// Weekdays the sharer's table covers; other days are unknown, not free.
  final List<int> days;
  final List<SharePeriod> periods;
  final List<String> names, rooms, teachers;
  final List<ShareSlot> slots;

  bool get hasRooms => rooms.isNotEmpty;
  bool get hasTeachers => teachers.isNotEmpty;

  /// Distinct course names, for the import preview.
  int get courseCount => names.length;

  String get includedFields =>
      ['時間', '課名', if (hasRooms) '教室', if (hasTeachers) '教師'].join('、');

  /// School courses only, unless [withCustom] is set for a comparison that
  /// never leaves the device.
  factory ScheduleSharePayload.fromSchedule(
    ClassSchedule schedule, {
    required String shareId,
    required ScheduleShareTerm term,
    required String nickname,
    required DateTime createdAt,
    bool includeRooms = false,
    bool includeTeachers = false,
    bool withCustom = false,
  }) {
    final columns = [
      for (final header in schedule.days)
        if (mondayBasedDay(header) case final day?) (header, day),
    ];
    final periods = <SharePeriod>[];
    final names = _StringTable(), rooms = _StringTable();
    final teachers = _StringTable();
    final slots = <ShareSlot>[];
    for (final period in schedule.periods) {
      final span = periodSpan(period.time);
      if (span == null) continue;
      final index = periods.length;
      periods.add(SharePeriod(clean(period.label), span.$1, span.$2));
      for (final (header, day) in columns) {
        final custom = withCustom ? period.custom[header] : null;
        final cell = custom != null
            ? ScheduleCell(custom.name, room: custom.classroom)
            : scheduleCell(period, header);
        if (cell == null) continue;
        final name = clean(cell.name);
        if (name.isEmpty) continue;
        final room = includeRooms ? clean(cell.room) : '';
        final teacher = includeTeachers ? clean(cell.teacher) : '';
        slots.add(
          ShareSlot(
            day,
            index,
            names.index(name),
            room.isEmpty ? null : rooms.index(room),
            teacher.isEmpty ? null : teachers.index(teacher),
          ),
        );
      }
    }
    return ScheduleSharePayload(
      shareId: shareId,
      term: term,
      createdAt: createdAt,
      nickname: cleanNickname(nickname),
      days: {for (final (_, day) in columns) day}.toList()..sort(),
      periods: periods,
      names: names.values,
      rooms: rooms.values,
      teachers: teachers.values,
      slots: slots,
    );
  }

  /// Monday-based weekday for a header such as 「星期三」.
  static int? mondayBasedDay(String header) {
    const words = ['一', '二', '三', '四', '五', '六', '日', '天'];
    for (final (i, word) in words.indexed) {
      if (header.contains(word)) return i == 7 ? 6 : i;
    }
    return null;
  }

  /// Start and end minutes of 「08:10~09:00」, parsed as on iOS so both apps
  /// skip the same rows.
  static (int, int)? periodSpan(String time) {
    final parts = time.split(RegExp('[~-]'));
    if (parts.length < 2) return null;
    int? minutes(String text) {
      final p = text.trim().split(':');
      if (p.length != 2) return null;
      final h = int.tryParse(p[0]), m = int.tryParse(p[1]);
      if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) {
        return null;
      }
      return h * 60 + m;
    }

    final start = minutes(parts[0]), end = minutes(parts[1]);
    if (start == null || end == null || start >= end) return null;
    return (start, end);
  }

  static const _bidi = {
    0x061C, 0x200E, 0x200F, 0x202A, 0x202B, 0x202C, 0x202D, 0x202E, //
    0x2066, 0x2067, 0x2068, 0x2069,
  };

  /// Unicode White_Space, which is what iOS splits on.
  static bool _space(int r) =>
      (r >= 0x09 && r <= 0x0D) ||
      r == 0x20 ||
      r == 0x85 ||
      r == 0xA0 ||
      r == 0x1680 ||
      (r >= 0x2000 && r <= 0x200A) ||
      r == 0x2028 ||
      r == 0x2029 ||
      r == 0x202F ||
      r == 0x205F ||
      r == 0x3000;

  /// Drops bidirectional overrides, turns control characters into spaces,
  /// collapses whitespace and caps the UTF-8 size on whole characters.
  static String clean(String text, {int maxBytes = maxTextBytes}) {
    final words = <String>[];
    final word = StringBuffer();
    for (final r in text.runes) {
      if (_bidi.contains(r)) continue;
      if (r < 0x20 || (r >= 0x7F && r <= 0x9F) || _space(r)) {
        if (word.isNotEmpty) words.add('$word');
        word.clear();
      } else {
        word.writeCharCode(r);
      }
    }
    if (word.isNotEmpty) words.add('$word');
    final result = StringBuffer();
    var bytes = 0;
    for (final character in words.join(' ').characters) {
      final size = utf8.encode(character).length;
      if (bytes + size > maxBytes) break;
      bytes += size;
      result.write(character);
    }
    return '$result';
  }

  static String cleanNickname(String text) =>
      clean(text).characters.take(maxNicknameLength).toString();

  /// A random UUID in the uppercase form iOS writes.
  static String newShareId([Random? random]) {
    final r = random ?? Random.secure();
    final b = [for (var i = 0; i < 16; i++) r.nextInt(256)];
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final hex = b.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
    return [
      hex.substring(0, 8),
      hex.substring(8, 12),
      hex.substring(12, 16),
      hex.substring(16, 20),
      hex.substring(20),
    ].join('-').toUpperCase();
  }

  static final _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  /// Short keys keep the QR small; slots are flattened as
  /// [day, period, name, room, teacher] with -1 for none. Keys are sorted,
  /// so the same table gives the same code.
  Map<String, Object> toWire() => {
    'a': [
      for (final p in periods) ...[p.start, p.end],
    ],
    'c': names,
    'd': days,
    if (teachers.isNotEmpty) 'e': teachers,
    'i': shareId,
    'n': nickname,
    'p': [for (final p in periods) p.id],
    if (rooms.isNotEmpty) 'r': rooms,
    's': term.semester,
    't': createdAt.millisecondsSinceEpoch ~/ 1000,
    'v': 1,
    'x': [
      for (final s in slots) ...[
        s.day,
        s.period,
        s.name,
        s.room ?? -1,
        s.teacher ?? -1,
      ],
    ],
    'y': term.academicYear,
  };

  String encoded() {
    final json = utf8.encode(jsonEncode(toWire()));
    final compressed = ZLibEncoder(raw: true, level: 9).convert(json);
    final text = prefix + base64Url.encode(compressed).replaceAll('=', '');
    if (text.length > maxEncodedLength) throw ScheduleShareError.tooLarge;
    return text;
  }

  /// Treats [text] as untrusted: every size, index and string is bounded
  /// before use.
  static ScheduleSharePayload decode(String text, {required DateTime now}) {
    final trimmed = text.trim();
    if (utf8.encode(trimmed).length > maxInputLength) {
      throw ScheduleShareError.tooLarge;
    }
    if (!trimmed.startsWith('NIUTT')) throw ScheduleShareError.notScheduleCode;
    if (!trimmed.startsWith(prefix)) {
      throw ScheduleShareError.unsupportedVersion;
    }
    final compressed = _base64Url(trimmed.substring(prefix.length));
    final json = compressed == null
        ? null
        : _inflate(compressed, maxDecompressedBytes);
    if (json == null) throw ScheduleShareError.malformed;
    final Object? wire;
    try {
      wire = jsonDecode(utf8.decode(json));
    } on FormatException {
      throw ScheduleShareError.malformed;
    }
    if (wire is! Map) throw ScheduleShareError.malformed;
    final payload = fromWire(wire);
    if (payload.slots.isEmpty) throw ScheduleShareError.empty;
    if (payload.createdAt.isAfter(now.add(clockSkew))) {
      throw ScheduleShareError.futureCode;
    }
    if (now.difference(payload.createdAt) > validity) {
      throw ScheduleShareError.expiredCode;
    }
    if (!payload.term.endDate.isAfter(now)) throw ScheduleShareError.termEnded;
    return payload;
  }

  /// Structure checks only; [decode] adds the time checks for fresh codes.
  static ScheduleSharePayload fromWire(Map<Object?, Object?> wire) {
    T field<T>(String key) {
      final value = wire[key];
      if (value is T) return value;
      throw ScheduleShareError.malformed;
    }

    List<T> list<T>(String key, {bool optional = false}) {
      final value = wire[key];
      if (value == null && optional) return const [];
      if (value is! List || value.any((v) => v is! T)) {
        throw ScheduleShareError.malformed;
      }
      return value.cast<T>();
    }

    final version = field<int>('v');
    final id = field<String>('i');
    final year = field<int>('y');
    final semester = field<int>('s');
    final created = field<int>('t');
    final nickname = field<String>('n');
    final days = list<int>('d');
    final ids = list<String>('p');
    final times = list<int>('a');
    final names = list<String>('c');
    final rooms = list<String>('r', optional: true);
    final teachers = list<String>('e', optional: true);
    final flat = list<int>('x');
    if (version != 1) throw ScheduleShareError.unsupportedVersion;

    if (ids.length > maxPeriods ||
        names.length > maxStrings ||
        rooms.length > maxStrings ||
        teachers.length > maxStrings ||
        flat.length > maxSlots * 5 ||
        days.length > 7) {
      throw ScheduleShareError.tooLarge;
    }
    if (!_uuid.hasMatch(id) ||
        semester < 1 ||
        semester > 2 ||
        year < 100 ||
        year > 300 ||
        times.length != ids.length * 2 ||
        flat.length % 5 != 0 ||
        days.toSet().length != days.length ||
        days.any((d) => d < 0 || d > 6)) {
      throw ScheduleShareError.malformed;
    }
    bool valid(List<String> values) => values.every(
      (v) =>
          v.isNotEmpty &&
          utf8.encode(v).length <= maxTextBytes &&
          clean(v) == v,
    );
    if (!valid(names) ||
        !valid(rooms) ||
        !valid(teachers) ||
        !ids.every(
          (v) => utf8.encode(v).length <= maxTextBytes && clean(v) == v,
        ) ||
        cleanNickname(nickname) != nickname) {
      throw ScheduleShareError.malformed;
    }

    final periods = <SharePeriod>[];
    for (var i = 0; i < ids.length; i++) {
      final start = times[i * 2], end = times[i * 2 + 1];
      if (start < 0 || start >= 1440 || end < 1 || end > 1440) {
        throw ScheduleShareError.malformed;
      }
      if (start >= end) throw ScheduleShareError.malformed;
      periods.add(SharePeriod(ids[i], start, end));
    }

    final slots = <ShareSlot>[];
    final occupied = <int>{};
    for (var o = 0; o < flat.length; o += 5) {
      final day = flat[o], period = flat[o + 1], name = flat[o + 2];
      final room = flat[o + 3], teacher = flat[o + 4];
      if (!days.contains(day) ||
          period < 0 ||
          period >= periods.length ||
          name < 0 ||
          name >= names.length ||
          (room != -1 && (room < 0 || room >= rooms.length)) ||
          (teacher != -1 && (teacher < 0 || teacher >= teachers.length)) ||
          !occupied.add(day * 100 + period)) {
        throw ScheduleShareError.malformed;
      }
      slots.add(
        ShareSlot(
          day,
          period,
          name,
          room == -1 ? null : room,
          teacher == -1 ? null : teacher,
        ),
      );
    }

    return ScheduleSharePayload(
      shareId: id,
      term: ScheduleShareTerm(year, semester),
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        created * 1000,
        isUtc: true,
      ),
      nickname: nickname,
      days: [...days]..sort(),
      periods: periods,
      names: names,
      rooms: rooms,
      teachers: teachers,
      slots: slots,
    );
  }

  static Uint8List? _base64Url(String text) {
    if (text.isEmpty || !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(text)) {
      return null;
    }
    try {
      return base64Url.decode(base64Url.normalize(text));
    } on FormatException {
      return null;
    }
  }

  /// Anything that inflates past [limit] is rejected rather than truncated.
  static Uint8List? _inflate(List<int> data, int limit) {
    final out = _LimitedSink(limit);
    try {
      ZLibDecoder(raw: true).startChunkedConversion(out)
        ..add(data)
        ..close();
    } catch (_) {
      return null;
    }
    final bytes = out.bytes.takeBytes();
    return bytes.isEmpty ? null : bytes;
  }

  /// The shared table in the same shape as the user's own, so it can use the
  /// same week view. Row indices match [periods].
  ClassSchedule toClassSchedule() {
    String clock(int m) =>
        '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
    return ClassSchedule(
      [for (final d in days) scheduleWeekdays[d]],
      [
        for (final (i, period) in periods.indexed)
          SchedulePeriod(
            period.id,
            '${clock(period.start)}~${clock(period.end)}',
            {
              for (final s in slots)
                if (s.period == i) scheduleWeekdays[s.day]: names[s.name],
            },
            const {},
            {
              for (final s in slots)
                if (s.period == i)
                  scheduleWeekdays[s.day]: ScheduleCell(
                    names[s.name],
                    teacher: s.teacher == null ? '' : teachers[s.teacher!],
                    room: s.room == null ? '' : rooms[s.room!],
                  ),
            },
          ),
      ],
    );
  }

  /// Breaks up to this long between two periods count as covered.
  static const maxCoveredBreak = 20;

  /// Whether the sharer's table says anything about [start]–[end] on [day].
  /// Rows the school omitted, or whose times failed to parse, never reach
  /// [periods], so those minutes stay unknown.
  bool covers(int day, int start, int end) {
    if (!days.contains(day)) return false;
    int? reached;
    for (final period in [
      ...periods,
    ]..sort((a, b) => a.start.compareTo(b.start))) {
      final current = reached;
      if (current != null && period.start - current <= maxCoveredBreak) {
        reached = max(current, period.end);
      } else if (period.start <= start) {
        reached = period.end;
      } else {
        break;
      }
      if (reached >= end) return true;
    }
    return false;
  }

  bool busy(int day, int start, int end) => slots.any((slot) {
    if (slot.day != day) return false;
    final other = periods[slot.period];
    return other.start < end && start < other.end;
  });

  /// Rows of this table, keyed `day * 100 + row`, where nobody here or in
  /// [others] has class. Times a table does not cover are left out rather
  /// than counted as free. Rows compare minutes, not period numbers, because
  /// two timetables may number their periods differently.
  Set<int> freeSlots(List<ScheduleSharePayload> others) {
    final everyone = [this, ...others];
    return {
      for (final (row, period) in periods.indexed)
        for (final day in days)
          if (everyone.every((p) => !p.busy(day, period.start, period.end)) &&
              everyone.every((p) => p.covers(day, period.start, period.end)))
            day * 100 + row,
    };
  }
}

class _StringTable {
  final values = <String>[];
  final _lookup = <String, int>{};
  int index(String value) =>
      _lookup.putIfAbsent(value, () => (values..add(value)).length - 1);
}

class _LimitedSink implements Sink<List<int>> {
  _LimitedSink(this.limit);
  final int limit;
  final bytes = BytesBuilder(copy: false);
  @override
  void add(List<int> data) {
    if (bytes.length + data.length > limit) throw ScheduleShareError.tooLarge;
    bytes.add(data);
  }

  @override
  void close() {}
}
