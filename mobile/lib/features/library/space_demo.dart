import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../core/time/campus_date.dart';
import 'space_models.dart';

/// Sample rooms with a few fixed bookings; reservations live in memory.
class DemoSpaceService implements SpaceService {
  DemoSpaceService();
  static final _reserved = <SpaceReservation>[];
  static var _nextId = 900;

  static const _groups = [
    SpaceGroup(5, '宜思智慧小間', total: 3),
    SpaceGroup(6, 'Switch相關設備', total: 1),
    SpaceGroup(8, '臨時研究小間', total: 2),
    SpaceGroup(10, '大型討論室', total: 3),
  ];
  static const _rooms = {
    5: [
      SpaceRoom(56, 'iSmart 504'),
      SpaceRoom(57, 'iSmart 505'),
      SpaceRoom(58, 'iSmart 506'),
    ],
    6: [SpaceRoom(59, 'Switch')],
    8: [SpaceRoom(61, '509研究小間'), SpaceRoom(67, '510研究小間')],
    10: [
      SpaceRoom(63, '523討論室'),
      SpaceRoom(64, '612討論室'),
      SpaceRoom(65, '314討論室'),
    ],
  };

  @override
  Future<bool> signedIn() async => true;

  @override
  Future<List<SpaceGroup>> groups() async => _groups;

  @override
  Future<SpaceSchedule> schedule(SpaceGroup group, CampusDate date) async {
    final rooms = _rooms[group.id] ?? const <SpaceRoom>[];
    final seed = date.day + group.id;
    return SpaceSchedule(
      group: group,
      date: date,
      rooms: rooms,
      bookings: [
        for (final (i, room) in rooms.indexed)
          if ((seed + i) % 3 != 0)
            SpaceBooking(
              roomId: room.id,
              start: (9 + (seed + i * 5) % 9) * 60,
              end: (11 + (seed + i * 5) % 9) * 60 + 30,
            ),
        for (final r in _reserved)
          if (r.date == date && rooms.any((room) => room.id == r.roomId))
            SpaceBooking(
              roomId: r.roomId,
              start: r.start,
              end: r.end,
              mine: true,
            ),
      ],
    );
  }

  @override
  Future<SpaceRules> rules(
    SpaceGroup group,
    SpaceRoom room,
    CampusDate date,
  ) async {
    final used = _reserved.fold<int>(0, (sum, r) => sum + r.minutes);
    return SpaceRules(
      open: group.id == 5 || group.id == 6 ? 8 * 60 : 8 * 60 + 30,
      close: 21 * 60 + 30,
      minHours: 1,
      maxHours: group.id == 6 ? 2 : 4,
      remainingHours: 28 - used / 60,
    );
  }

  @override
  Future<List<SpaceReservation>> mine() async => List.of(_reserved);

  @override
  Future<void> reserve(
    SpaceGroup group,
    SpaceRoom room,
    CampusDate date,
    Minute start,
    Minute end,
  ) async {
    final current = await schedule(group, date);
    if (!current.isFree(room.id, start, end)) {
      throw const SpaceException('這個時段已經有人預約或不開放。');
    }
    _reserved.add(
      SpaceReservation(
        id: _nextId++,
        roomId: room.id,
        roomName: room.name,
        date: date,
        start: start,
        endDate: date,
        end: end,
        state: ReservationState.reserved,
        keepUntil: (date, start + 15),
      ),
    );
  }

  @override
  Future<void> cancel(SpaceReservation reservation) async =>
      _reserved.removeWhere((r) => r.id == reservation.id);

  @override
  void close() {}

  /// Test hook: start every run from an empty list.
  @visibleForTesting
  static void reset() => _reserved.clear();
}
