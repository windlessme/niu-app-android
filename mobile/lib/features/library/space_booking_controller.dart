import 'package:flutter/foundation.dart';

import '../../core/analytics/app_analytics.dart';
import '../../core/time/campus_date.dart';
import 'space_models.dart';

enum SpacePhase { connecting, signIn, ready, failed }

/// A booking ready to send, checked against fresh schedule and rules.
class SpaceDraft {
  const SpaceDraft({
    required this.group,
    required this.room,
    required this.date,
    required this.start,
    required this.end,
    required this.rules,
  });
  final SpaceGroup group;
  final SpaceRoom room;
  final CampusDate date;
  final Minute start, end;
  final SpaceRules rules;
  String get timeLabel => '${formatMinute(start)}–${formatMinute(end)}';
  int get minutes => end - start;
}

/// Outcome of a confirmed change, for the result dialog.
class SpaceCompletion {
  const SpaceCompletion({
    required this.reserved,
    required this.roomName,
    required this.date,
    required this.start,
    required this.end,
    this.refreshFailed = false,
  });
  final bool reserved;
  final String roomName;
  final CampusDate date;
  final Minute start, end;
  final bool refreshFailed;
  String get title => reserved ? '預約完成' : '已取消預約';
  String get message => [
    roomName,
    '${webpacDate(date)} ${formatMinute(start)}–${formatMinute(end)}',
    reserved ? '請依圖書館規定準時報到，可在「我的預約」查看。' : '這筆預約已經取消。',
    if (refreshFailed) '清單更新失敗，請重新整理。',
  ].join('\n');
}

/// State behind 設備預約, mirroring the iOS flow: date → group/room → start
/// slot, then length; every change is re-checked against fresh data.
class SpaceBookingController extends ChangeNotifier {
  SpaceBookingController({
    required this.restore,
    required this.signInWith,
    required this.now,
  });

  /// A signed-in service, or null when the reader must sign in.
  final Future<SpaceService?> Function() restore;
  final Future<SpaceService> Function(String password) signInWith;
  final DateTime Function() now;

  SpaceService? _service;
  SpacePhase phase = SpacePhase.connecting;
  List<SpaceGroup> groups = const [];
  int? groupId, roomId;
  late CampusDate date = today;
  SpaceSchedule? schedule;
  SpaceRules? rules;
  List<SpaceReservation> reservations = const [];
  DateTime? updatedAt, reservationsUpdatedAt;
  bool loading = false, mutating = false, needsVerification = false;
  bool signingIn = false;
  String? error, notice, selectionMessage, signInError;
  Minute? start;
  int duration = 60;
  int _generation = 0;
  bool _disposed = false;

  CampusDate get today => CampusDate.at(now());

  /// Taipei minute when [date] is today; all-day when past; null when ahead.
  Minute? get nowMinute {
    final offset = daysBetween(today, date);
    if (offset > 0) return null;
    if (offset < 0) return 24 * 60;
    final t = now().toUtc().add(const Duration(hours: 8));
    return t.hour * 60 + t.minute;
  }

  SpaceGroup? get group => groups.where((g) => g.id == groupId).firstOrNull;
  List<SpaceRoom> get rooms => schedule?.rooms ?? const [];
  SpaceRoom? get room => rooms.where((r) => r.id == roomId).firstOrNull;
  bool get busy => loading || mutating;

  List<SpaceSlot> get slots {
    final s = schedule, r = rules, id = roomId;
    if (s == null || r == null || id == null) return const [];
    return spaceSlots(s, id, r, now: nowMinute);
  }

  int get minDuration => rules?.minMinutes ?? 60;

  /// Longest length for the chosen start, or null without one.
  int? get maxDuration {
    final s = schedule, r = rules, id = roomId, from = start;
    if (s == null || r == null || id == null || from == null) return null;
    return longestFrom(s, id, r, from, now: nowMinute);
  }

  String? get selectionError {
    final s = schedule, r = rules, id = roomId, from = start;
    if (from == null) return '請點選開始時間。';
    if (s == null || r == null || id == null) return '請先選擇設備。';
    return checkSelection(s, id, r, from, duration, now: nowMinute);
  }

  String? get timeLabel => start == null || selectionError != null
      ? null
      : '${formatMinute(start!)}–${formatMinute(start! + duration)}';

  bool isSelected(Minute m) =>
      selectionError == null &&
      start != null &&
      m >= start! &&
      m < start! + duration;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _service?.close();
    super.dispose();
  }

  bool _current(int generation) => !_disposed && generation == _generation;

  Future<void> connect() async {
    final generation = ++_generation;
    phase = SpacePhase.connecting;
    error = null;
    _notify();
    try {
      final service = await restore();
      if (!_current(generation)) return service?.close();
      if (service == null) {
        phase = SpacePhase.signIn;
        return _notify();
      }
      _service = service;
      await _loadAll(generation);
      if (_current(generation)) phase = SpacePhase.ready;
    } catch (e) {
      if (!_current(generation)) return;
      if (e is SpaceSignInRequired) {
        _service?.close();
        _service = null;
        phase = SpacePhase.signIn;
      } else {
        phase = SpacePhase.failed;
        error = _message(e);
      }
    }
    _notify();
  }

  Future<void> signIn(String password) async {
    if (password.isEmpty || signingIn) return;
    final generation = ++_generation;
    signingIn = true;
    signInError = null;
    _notify();
    try {
      final service = await signInWith(password);
      if (!_current(generation)) return service.close();
      _service?.close();
      _service = service;
      await _loadAll(generation);
      if (_current(generation)) phase = SpacePhase.ready;
    } catch (e) {
      if (_current(generation)) signInError = _message(e);
    } finally {
      if (_current(generation)) signingIn = false;
      _notify();
    }
  }

  /// Signed out on the library side: drop the service and ask again.
  void signedOut() {
    _generation++;
    _service?.close();
    _service = null;
    phase = SpacePhase.signIn;
    loading = mutating = false;
    _notify();
  }

  Future<void> refresh() => _read((g) => _loadAll(g));

  void selectDate(CampusDate value) {
    if (mutating || value == date) return;
    date = value;
    _clearDay();
    refresh();
  }

  void selectGroup(int id) {
    if (mutating || id == groupId) return;
    groupId = id;
    roomId = null;
    _clearDay();
    refresh();
  }

  void selectRoom(int id) {
    if (mutating || id == roomId) return;
    roomId = id;
    rules = null;
    start = null;
    selectionMessage = null;
    refresh();
  }

  void selectStart(Minute m) {
    final s = schedule, r = rules, id = roomId;
    if (busy || s == null || r == null || id == null || m == start) return;
    final problem = checkSelection(s, id, r, m, r.minMinutes, now: nowMinute);
    if (problem != null) {
      selectionMessage = problem;
    } else {
      start = m;
      duration = r.minMinutes;
      selectionMessage = null;
    }
    _notify();
  }

  void setDuration(int minutes) {
    final max = maxDuration;
    if (busy || max == null) return;
    duration = (minutes ~/ 30 * 30).clamp(minDuration, max);
    selectionMessage = null;
    _notify();
  }

  /// Fresh schedule and rules for the selection; null when it no longer fits.
  Future<SpaceDraft?> prepare() async {
    final g = group, rm = room, from = start;
    final service = _service;
    if (busy || needsVerification || g == null || rm == null || from == null) {
      return null;
    }
    if (service == null) return null;
    final generation = _generation;
    loading = true;
    error = null;
    _notify();
    try {
      return await _fresh(service, g, rm, date, from, from + duration);
    } catch (e) {
      if (_current(generation)) _fail(e);
      return null;
    } finally {
      if (_current(generation)) loading = false;
      _notify();
    }
  }

  Future<SpaceDraft?> _fresh(
    SpaceService service,
    SpaceGroup g,
    SpaceRoom rm,
    CampusDate day,
    Minute from,
    Minute to,
  ) async {
    if (!await service.signedIn()) throw const SpaceSignInRequired();
    final freshSchedule = await service.schedule(g, day);
    final freshRules = await service.rules(g, rm, day);
    schedule = freshSchedule;
    rules = freshRules;
    updatedAt = now();
    final problem = checkSelection(
      freshSchedule,
      rm.id,
      freshRules,
      from,
      to - from,
      now: nowMinute,
    );
    if (problem != null) {
      start = null;
      selectionMessage = '原選取時段已無法預約，請重新選擇開始時間。';
      return null;
    }
    return SpaceDraft(
      group: g,
      room: rm,
      date: day,
      start: from,
      end: to,
      rules: freshRules,
    );
  }

  /// Sends [draft] after one more check. Never retried automatically.
  Future<SpaceCompletion?> submit(SpaceDraft draft) => _change(
    () async {
      final fresh = await _fresh(
        _service!,
        draft.group,
        draft.room,
        draft.date,
        draft.start,
        draft.end,
      );
      if (fresh == null) {
        throw const SpaceException('時段剛被預約或已開始，請重新選擇。');
      }
      await _service!.reserve(
        fresh.group,
        fresh.room,
        fresh.date,
        fresh.start,
        fresh.end,
      );
      start = null;
    },
    SpaceCompletion(
      reserved: true,
      roomName: draft.room.name,
      date: draft.date,
      start: draft.start,
      end: draft.end,
    ),
  );

  Future<SpaceCompletion?> cancel(SpaceReservation r) => _change(
    () => _service!.cancel(r),
    SpaceCompletion(
      reserved: false,
      roomName: r.roomName,
      date: r.date,
      start: r.start,
      end: r.end,
    ),
  );

  void acknowledgeVerification() {
    if (loading || reservationsUpdatedAt == null) return;
    needsVerification = false;
    notice = null;
    _notify();
  }

  Future<SpaceCompletion?> _change(
    Future<void> Function() action,
    SpaceCompletion success,
  ) async {
    if (_service == null || busy || needsVerification) return null;
    final generation = _generation;
    mutating = true;
    error = notice = null;
    _notify();
    final event = success.reserved ? 'library_reserve' : 'library_cancel';
    try {
      await action();
      AppAnalytics.instance.event(event, {'result': 'success'});
      if (!_current(generation)) return null;
      notice = success.reserved ? '預約已完成。' : '預約已取消。';
      var result = success;
      try {
        await _loadAll(generation);
      } catch (e) {
        if (!_current(generation)) return null;
        result = SpaceCompletion(
          reserved: success.reserved,
          roomName: success.roomName,
          date: success.date,
          start: success.start,
          end: success.end,
          refreshFailed: true,
        );
        notice = '${notice!}清單更新失敗，請重新整理。';
      }
      return result;
    } catch (e) {
      AppAnalytics.instance.event(event, {
        'result': e is SpaceUncertain ? 'unconfirmed' : 'failure',
      });
      if (!_current(generation)) return null;
      if (e is SpaceUncertain) {
        needsVerification = true;
        reservationsUpdatedAt = null;
        notice = e.message;
      } else {
        _fail(e);
      }
      return null;
    } finally {
      if (_current(generation)) mutating = false;
      _notify();
    }
  }

  Future<void> _read(Future<void> Function(int generation) action) async {
    if (mutating) return;
    if (_service == null) return connect();
    final generation = ++_generation;
    loading = true;
    error = null;
    _notify();
    try {
      await action(generation);
    } catch (e) {
      if (_current(generation)) _fail(e);
    } finally {
      if (_current(generation)) loading = false;
      _notify();
    }
  }

  void _fail(Object e) {
    if (e is SpaceSignInRequired) return signedOut();
    error = _message(e);
  }

  Future<void> _loadAll(int generation) async {
    final service = _service!;
    if (!await service.signedIn()) throw const SpaceSignInRequired();
    final list = await service.groups();
    if (!_current(generation)) return;
    groups = list;
    if (group == null) {
      final had = start != null;
      groupId = list.firstOrNull?.id;
      roomId = null;
      _clearDay();
      if (had) selectionMessage = '原設備類別已無法選擇，請重新選取時段。';
    }
    // Own records first, so a closed day never blocks checking them.
    final records = await service.mine();
    if (!_current(generation)) return;
    reservations = records;
    reservationsUpdatedAt = now();
    final g = group;
    if (g == null) return _notify();
    final day = await service.schedule(g, date);
    if (!_current(generation)) return;
    schedule = day;
    if (room == null) {
      final had = start != null;
      roomId = day.rooms.firstOrNull?.id;
      start = null;
      rules = null;
      if (had) selectionMessage = '原設備已無法選擇，請重新選取時段。';
    }
    final rm = room;
    if (rm == null) {
      rules = null;
      return _notify();
    }
    try {
      rules = await service.rules(g, rm, date);
    } on SpaceException catch (e) {
      if (!_current(generation)) return;
      rules = null;
      start = null;
      selectionMessage = e.message;
      return _notify();
    }
    if (!_current(generation)) return;
    updatedAt = now();
    // A selection that stopped fitting is cleared, never silently moved.
    if (start != null && selectionError != null) {
      start = null;
      selectionMessage = '原選取時段已無法預約，請重新選擇開始時間。';
    }
    _notify();
  }

  void _clearDay() {
    schedule = null;
    rules = null;
    updatedAt = null;
    start = null;
    selectionMessage = null;
  }

  static String _message(Object e) =>
      e is SpaceException ? e.message : '無法取得圖書館資料，請檢查網路後重新整理。';
}
