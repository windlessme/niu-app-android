import 'dart:convert';

import '../../core/time/campus_date.dart';

/// Library rooms and devices (研究小間、討論室、Switch) bookable on webpacx.
class SpaceGroup {
  const SpaceGroup(this.id, this.name, {this.total = 0});
  final int id;
  final String name;

  /// Number of rooms or devices in the group.
  final int total;
}

class SpaceRoom {
  const SpaceRoom(this.id, this.name);
  final int id;
  final String name;
}

/// Minutes since local midnight in Taipei.
typedef Minute = int;

String formatMinute(Minute m) =>
    '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

/// `/` separated date the library expects, e.g. 2026/10/02.
String webpacDate(CampusDate d) =>
    '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

/// 1、1.5、2 — hours without a trailing `.0`.
String formatHours(num hours) {
  final rounded = (hours * 10).round() / 10;
  return rounded == rounded.roundToDouble() ? '${rounded.round()}' : '$rounded';
}

CampusDate addDays(CampusDate date, int days) {
  final d = DateTime.utc(date.year, date.month, date.day + days);
  return CampusDate(d.year, d.month, d.day);
}

int daysBetween(CampusDate from, CampusDate to) => DateTime.utc(
  to.year,
  to.month,
  to.day,
).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];

/// 週四
String shortWeekday(CampusDate d) =>
    '週${_weekdays[DateTime.utc(d.year, d.month, d.day).weekday - 1]}';

/// 今天、明天、後天, or null further out.
String? relativeDay(CampusDate d, CampusDate today) =>
    switch (daysBetween(today, d)) {
      0 => '今天',
      1 => '明天',
      2 => '後天',
      _ => null,
    };

/// 今天 · 10/1（週四）
String dayTitle(CampusDate d, CampusDate today) {
  final base = '${d.month}/${d.day}（${shortWeekday(d)}）';
  final relative = relativeDay(d, today);
  return relative == null ? base : '$relative · $base';
}

/// A booked interval on one day for one room; [mine] when it is the reader's.
class SpaceBooking {
  const SpaceBooking({
    required this.roomId,
    required this.start,
    required this.end,
    this.mine = false,
  });
  final int roomId;
  final Minute start, end;
  final bool mine;
}

/// Rooms of a group and their bookings on one day.
class SpaceSchedule {
  const SpaceSchedule({
    required this.group,
    required this.date,
    required this.rooms,
    required this.bookings,
  });
  final SpaceGroup group;
  final CampusDate date;
  final List<SpaceRoom> rooms;
  final List<SpaceBooking> bookings;

  List<SpaceBooking> of(int roomId) => [
    for (final b in bookings)
      if (b.roomId == roomId) b,
  ];

  bool isFree(int roomId, Minute start, Minute end) => !bookings.any(
    (b) => b.roomId == roomId && b.start < end && start < b.end,
  );

  /// Clip multi-day bookings (e.g. 長期研究小間) to this day.
  static SpaceBooking? clip(
    CampusDate day,
    int roomId,
    String? start,
    String? end,
    bool mine,
  ) {
    final s = parseStamp(start), e = parseStamp(end);
    if (s == null || e == null) return null;
    if (e.$1.compareTo(day) < 0 || s.$1.compareTo(day) > 0) return null;
    final from = s.$1.compareTo(day) < 0 ? 0 : s.$2;
    final to = e.$1.compareTo(day) > 0 ? 24 * 60 : e.$2;
    if (to <= from) return null;
    return SpaceBooking(roomId: roomId, start: from, end: to, mine: mine);
  }
}

/// A reader's limits for one room on one day. Units are hours.
class SpaceRules {
  const SpaceRules({
    required this.open,
    required this.close,
    required this.minHours,
    required this.maxHours,
    required this.remainingHours,
  });
  final Minute open, close;
  final double minHours, maxHours;

  /// Total allowance left (`maxCanReserveTotalUnit − inReserve`).
  final double remainingHours;

  /// Shortest booking, rounded up to the 30-minute grid.
  int get minMinutes => (minHours * 2).ceil() * 30;
  int get maxMinutes => (maxHours * 2).floor() * 30;
  bool get quotaExhausted => remainingHours < minHours;

  static SpaceRules parse(String raw) {
    final data = jsonDecode(raw) as Map;
    double? hours(String key) => double.tryParse('${data[key] ?? ''}');
    final total =
        hours('maxCanReserveTotalUnit') ?? hours('canReserveTotalUnit') ?? 0;
    final used = hours('inReserve') ?? 0;
    final min = hours('canReserveMinUnit') ?? 0;
    final max = hours('canReserveMaxUnit') ?? 0;
    return SpaceRules(
      open: parseClock('${data['openTime']}') ?? 8 * 60,
      close: parseClock('${data['closeTime']}') ?? 22 * 60,
      minHours: min > 0 ? min : 1,
      maxHours: max > 0 ? max : 4,
      remainingHours: (total - used).clamp(0, double.infinity).toDouble(),
    );
  }
}

Minute? parseClock(String text) {
  final m = RegExp(r'^(\d{1,2}):?(\d{2})$').firstMatch(text.trim());
  if (m == null) return null;
  final h = int.parse(m[1]!), min = int.parse(m[2]!);
  if (h > 24 || min > 59) return null;
  return h * 60 + min;
}

/// `2026-10-02 10:00:00.0` → date and minute of day.
(CampusDate, Minute)? parseStamp(String? text) {
  final m = RegExp(
    r'^(\d{4})[-/](\d{2})[-/](\d{2})[ T](\d{2}):(\d{2})',
  ).firstMatch(text ?? '');
  if (m == null) return null;
  return (
    CampusDate(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!)),
    int.parse(m[4]!) * 60 + int.parse(m[5]!),
  );
}

enum ReservationState { reserved, inUse }

/// A reader's own reservation or current use, from 我的預約.
class SpaceReservation {
  const SpaceReservation({
    required this.id,
    required this.roomId,
    required this.roomName,
    required this.date,
    required this.start,
    required this.endDate,
    required this.end,
    required this.state,
    this.keepUntil,
  });

  /// `equipmentCirContent.id`, the handle the library cancels by.
  final int id;
  final int roomId;
  final String roomName;
  final CampusDate date, endDate;
  final Minute start, end;
  final ReservationState state;

  /// Hold deadline; the booking lapses if not checked in by then.
  final (CampusDate, Minute)? keepUntil;

  int get minutes => daysBetween(date, endDate) * 24 * 60 + end - start;

  /// Whether the booking overlaps [from, to) days.
  bool overlaps(CampusDate from, CampusDate to) =>
      date.compareTo(to) < 0 &&
      (endDate.compareTo(from) > 0 || (endDate == from && end > 0));
}

class SpaceException implements Exception {
  const SpaceException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// A change was sent but its outcome is unknown; never resend blindly.
class SpaceUncertain extends SpaceException {
  const SpaceUncertain() : super('還無法確認圖書館是否完成操作。請先重新整理「我的預約」核對，不要立刻重複送出。');
}

/// The library session ended; sign in again.
class SpaceSignInRequired extends SpaceException {
  const SpaceSignInRequired() : super('圖書館登入已失效，請重新登入。');
}

/// The library's failure keys (`common:cir.eqReserve.failed.*`) in words.
String describeReserveFailure(String? message) {
  final key = (message ?? '').split('.').last;
  return const {
        'overUserUnits': '已達可預約的群組數上限。',
        'timeNotReached': '這個時段還不開放預約。',
        'groupUnits': '超過這類設備可預約的總時數。',
        'baseUnitsGT': '預約時間未達單次下限。',
        'timeGroupDup': '同一時段已預約了同類設備。',
        'baseUnits': '預約時間不符單次時數上下限。',
        'userMaxDays': '超過可預約的天數範圍。',
        'timeStartError': '開始時間不在開放時間內。',
        'timeDup': '這個時段已經有人預約或不開放。',
        'baseUnitsLT': '超過單次可預約的時數上限。',
        'ValidateReserved': '這個時段已被預約。',
      }[key] ??
      (message == null ||
              message.isEmpty ||
              message.startsWith('common:') ||
              message.startsWith('personal:')
          ? '預約沒有成功，請換個時段再試。'
          : message);
}

/// What the 設備預約 screen needs; the library site or the review demo.
abstract interface class SpaceService {
  /// Whether the library still has this reader signed in.
  Future<bool> signedIn();
  Future<List<SpaceGroup>> groups();
  Future<SpaceSchedule> schedule(SpaceGroup group, CampusDate date);
  Future<SpaceRules> rules(SpaceGroup group, SpaceRoom room, CampusDate date);
  Future<List<SpaceReservation>> mine();
  Future<void> reserve(
    SpaceGroup group,
    SpaceRoom room,
    CampusDate date,
    Minute start,
    Minute end,
  );
  Future<void> cancel(SpaceReservation reservation);
  void close();
}

// ── Time slots ─────────────────────────────────────────────────────────────

enum SlotState { available, occupied, mine, past, tooShort, quota }

/// One 30-minute cell of the day for a room.
class SpaceSlot {
  const SpaceSlot(this.minute, this.state, this.continuous);
  final Minute minute;
  final SlotState state;

  /// Free minutes from here until the next booking or closing.
  final int continuous;
}

/// [now] is the Taipei minute when [schedule] is today, 24:00 when the day
/// is past, and null when it is ahead.
List<SpaceSlot> spaceSlots(
  SpaceSchedule schedule,
  int roomId,
  SpaceRules rules, {
  Minute? now,
}) {
  final booked = schedule.of(roomId);
  final first = (rules.open + 29) ~/ 30 * 30;
  return [
    for (var m = first; m + 30 <= rules.close; m += 30)
      () {
        final over = booked.where((b) => b.start < m + 30 && m < b.end);
        final next = booked
            .where((b) => b.start >= m)
            .fold<Minute>(rules.close, (a, b) => b.start < a ? b.start : a);
        final continuous = (next < rules.close ? next : rules.close) - m;
        final state = now != null && m < now
            ? SlotState.past
            : over.isNotEmpty
            ? (over.any((b) => b.mine) ? SlotState.mine : SlotState.occupied)
            : rules.quotaExhausted
            ? SlotState.quota
            : continuous < rules.minMinutes
            ? SlotState.tooShort
            : SlotState.available;
        return SpaceSlot(m, state, continuous < 0 ? 0 : continuous);
      }(),
  ];
}

/// Why [start]–[start]+[minutes] cannot be booked, or null when it can.
String? checkSelection(
  SpaceSchedule schedule,
  int roomId,
  SpaceRules rules,
  Minute start,
  int minutes, {
  Minute? now,
}) {
  final end = start + minutes;
  if (start % 30 != 0 ||
      minutes % 30 != 0 ||
      start < rules.open ||
      end > rules.close ||
      minutes < rules.minMinutes ||
      minutes > rules.maxMinutes ||
      minutes / 60 > rules.remainingHours) {
    return '所選時段不符合開放時間、單次時數或剩餘額度，請重新選擇。';
  }
  if ((now != null && start < now) || !schedule.isFree(roomId, start, end)) {
    return '所選時段已開始或已被預約，請重新整理後選擇其他時段。';
  }
  return null;
}

/// Longest valid length from [start], or null when even the minimum fails.
int? longestFrom(
  SpaceSchedule schedule,
  int roomId,
  SpaceRules rules,
  Minute start, {
  Minute? now,
}) {
  int? best;
  for (var l = rules.minMinutes; l <= rules.maxMinutes; l += 30) {
    if (checkSelection(schedule, roomId, rules, start, l, now: now) != null) {
      break;
    }
    best = l;
  }
  return best;
}

// ── My reservations ────────────────────────────────────────────────────────

enum ReservationPeriod {
  all('全部日期'),
  today('今天'),
  tomorrow('明天'),
  week('一週');

  const ReservationPeriod(this.label);
  final String label;
}

List<SpaceReservation> filterReservations(
  List<SpaceReservation> list, {
  required CampusDate today,
  String query = '',
  ReservationPeriod period = ReservationPeriod.all,
  int? roomId,
}) {
  final terms = query
      .trim()
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((t) => t.isNotEmpty);
  final (from, to) = switch (period) {
    ReservationPeriod.all => (null, null),
    ReservationPeriod.today => (today, addDays(today, 1)),
    ReservationPeriod.tomorrow => (addDays(today, 1), addDays(today, 2)),
    ReservationPeriod.week => (today, addDays(today, 7)),
  };
  String stamp(CampusDate d, Minute m) =>
      '${webpacDate(d)} ${formatMinute(m)} $d';
  return [
    for (final r in list)
      if ((roomId == null || r.roomId == roomId) &&
          (from == null || r.overlaps(from, to!)) &&
          terms.every(
            [
              r.roomName,
              stamp(r.date, r.start),
              stamp(r.endDate, r.end),
              shortWeekday(r.date),
              '星期${shortWeekday(r.date).substring(1)}',
            ].join(' ').toLowerCase().contains,
          ))
        r,
  ]..sort((a, b) {
    final byDate = a.date.compareTo(b.date);
    if (byDate != 0) return byDate;
    return a.start != b.start ? a.start - b.start : a.id - b.id;
  });
}
