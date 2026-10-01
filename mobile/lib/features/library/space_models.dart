import 'dart:convert';

import '../../core/time/campus_date.dart';

/// Library rooms and devices (研究小間、討論室、Switch) bookable on webpacx.
class SpaceGroup {
  const SpaceGroup(this.id, this.name);
  final int id;
  final String name;
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

/// Per-group policy for a reader on a given day. Units are hours.
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

  /// Hours still bookable within this group (total minus already reserved).
  final double remainingHours;

  int get minMinutes => (minHours * 60).round();
  int get maxMinutes => (maxHours * 60).round();

  static SpaceRules parse(String raw) {
    final data = jsonDecode(raw) as Map;
    double hours(String key) => double.tryParse('${data[key] ?? ''}') ?? 0;
    final total = hours('canReserveTotalUnit');
    final used = hours('inReserve');
    return SpaceRules(
      open: parseClock('${data['openTime']}') ?? 8 * 60,
      close: parseClock('${data['closeTime']}') ?? 22 * 60,
      minHours: hours('canReserveMinUnit') > 0 ? hours('canReserveMinUnit') : 1,
      maxHours: hours('canReserveMaxUnit') > 0 ? hours('canReserveMaxUnit') : 4,
      remainingHours: total > 0 ? (total - used).clamp(0, total) : 0,
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

/// One day's availability for every room of a group.
class SpaceDay {
  const SpaceDay({
    required this.group,
    required this.date,
    required this.rooms,
    required this.bookings,
    required this.rules,
  });
  final SpaceGroup group;
  final CampusDate date;
  final List<SpaceRoom> rooms;
  final List<SpaceBooking> bookings;
  final SpaceRules rules;

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

enum ReservationState { reserved, inUse }

/// A reader's own reservation or current use, from 我的預約.
class SpaceReservation {
  const SpaceReservation({
    required this.id,
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
  final String roomName;
  final CampusDate date, endDate;
  final Minute start, end;
  final ReservationState state;

  /// Check-in deadline; the booking lapses if unused by then.
  final Minute? keepUntil;
}

class SpaceException implements Exception {
  const SpaceException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The library's failure keys (`common:cir.eqReserve.failed.*`) in words.
String describeReserveFailure(String? message) {
  final key = (message ?? '').split('.').last;
  return const {
        'overUserUnits': '已達可預約的群組數上限。',
        'timeNotReached': '這個時段還不開放預約。',
        'groupUnits': '超過這類空間可預約的總時數。',
        'baseUnitsGT': '預約時間未達單次下限。',
        'timeGroupDup': '同一時段已預約了同類空間。',
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

/// What the 空間預約 screen needs; the library site or the review demo.
abstract interface class SpaceService {
  Future<List<SpaceGroup>> groups();
  Future<SpaceDay> day(SpaceGroup group, CampusDate date);
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

/// Free stretches of [room] on [day], from [earliest] on, at least [min] long.
List<(Minute, Minute)> freeIntervals(
  SpaceDay day,
  int roomId, {
  Minute earliest = 0,
  int? min,
}) {
  final rules = day.rules;
  var cursor = earliest > rules.open ? earliest : rules.open;
  final booked = day.of(roomId)..sort((a, b) => a.start.compareTo(b.start));
  final free = <(Minute, Minute)>[];
  for (final b in booked) {
    if (b.end <= cursor) continue;
    if (b.start > cursor) {
      free.add((cursor, b.start < rules.close ? b.start : rules.close));
    }
    if (b.end > cursor) cursor = b.end;
    if (cursor >= rules.close) break;
  }
  if (cursor < rules.close) free.add((cursor, rules.close));
  final need = min ?? rules.minMinutes;
  return [
    for (final f in free)
      if (f.$2 - f.$1 >= need) f,
  ];
}
