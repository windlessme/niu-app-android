import 'package:shared_preferences/shared_preferences.dart';

import '../../core/analytics/app_analytics.dart';
import '../../core/platform/schedule_gateway.dart';
import '../../core/session/campus_session.dart';
import '../../core/time/campus_date.dart';
import '../academic_calendar/calendar_repository.dart';
import '../events/event_models.dart';
import '../moodle/course_presentation.dart';
import '../moodle/moodle_repository.dart';
import '../schedule/custom_courses.dart';
import '../schedule/schedule_export.dart';
import '../schedule/schedule_models.dart';

/// Local notifications, matching the iOS app: assignment deadlines a day
/// ahead, important calendar dates the morning before, and weekly class
/// reminders. Everything is computed on the device and handed to Android;
/// there is no push server.
class CampusNotifications {
  CampusNotifications({
    required this.session,
    required this.moodle,
    required this.calendar,
    this.events,
    this.gateway = const ScheduleGateway(),
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;
  final CampusSession session;

  /// The student's 「我的報名」, read from the school for event reminders.
  final Future<List<CampusEvent>> Function()? events;
  final Future<MoodleRepository?> Function() moodle;
  final CalendarRepository calendar;
  final ScheduleGateway gateway;
  final DateTime Function() clock;

  static const assignmentsKey = 'notify.assignments';
  static const calendarKey = 'notify.calendar';
  static const eventsKey = 'notify.events';

  /// Minutes before a registered event starts: 1 day, 1 hour or 30 minutes.
  static const eventLeadKey = 'notify.events.lead';
  static const eventLeads = {1440: '1 天', 60: '1 小時', 30: '30 分鐘'};

  Future<int> eventLead() async {
    final value = (await SharedPreferences.getInstance()).getInt(eventLeadKey);
    return eventLeads.containsKey(value) ? value! : 1440;
  }

  Future<void> setEventLead(int minutes) async {
    if (!eventLeads.containsKey(minutes)) return;
    await (await SharedPreferences.getInstance()).setInt(eventLeadKey, minutes);
    await refresh();
  }

  Future<void> _queue = Future.value();

  Future<bool> enabled(String key) async =>
      (await SharedPreferences.getInstance()).getBool(key) ?? false;

  Future<void> setEnabled(String key, bool value) async {
    await (await SharedPreferences.getInstance()).setBool(key, value);
    AppAnalytics.instance.event('notification_setting', {
      'kind': switch (key) {
        assignmentsKey => 'assignments',
        eventsKey => 'events',
        _ => 'calendar',
      },
      'enabled': value ? 'on' : 'off',
    });
    await refresh();
  }

  /// Turns class reminders on with the saved semester dates, or the current
  /// semester from the academic calendar.
  Future<void> setClassReminders(bool value) async {
    if (value) {
      await _queue;
      await _saveSchedule(requireDates: true);
    }
    final applied = await gateway.setReminders(enabled: value);
    AppAnalytics.instance.event('notification_setting', {
      'kind': 'classes',
      'enabled': value ? (applied ? 'on' : 'denied') : 'off',
    });
    if (!applied && value) {
      throw StateError('通知權限未開啟');
    }
  }

  /// Turns the in-class notification on with the saved semester dates, or
  /// the current semester from the academic calendar.
  Future<void> setClassNow(bool value) async {
    if (value) {
      await _queue;
      await _saveSchedule(requireDates: true);
    }
    final applied = await gateway.setClassNow(enabled: value);
    AppAnalytics.instance.event('notification_setting', {
      'kind': 'class_now',
      'enabled': value ? (applied ? 'on' : 'denied') : 'off',
    });
    if (!applied && value) {
      throw StateError('通知權限未開啟');
    }
  }

  /// Recomputes every enabled kind. Calls are serialized; a failure in one
  /// kind does not stop the others and is rethrown at the end.
  Future<void> refresh() {
    final next = _queue.catchError((Object _) {}).then((_) => _refresh());
    _queue = next;
    return next;
  }

  /// Recomputes event reminders alone, right after a registration change.
  /// [registrations] is a 「我的報名」 list just read; without one the school
  /// is asked again.
  Future<void> refreshEvents([List<CampusEvent>? registrations]) {
    final next = _queue.catchError((Object _) {}).then((_) async {
      final account = session.account;
      if (account == null || !session.hasLocalAccount) return;
      final epoch = session.coordinator.epoch;
      final items = await enabled(eventsKey)
          ? await _events(registrations)
          : <CampusNotice>[];
      session.coordinator.requireCurrent(epoch);
      if (session.account != account) throw StateError('帳號已變更');
      await gateway.setNotifications('events', items);
    });
    _queue = next;
    return next;
  }

  Future<void> _refresh() async {
    final account = session.account;
    if (account == null || !session.hasLocalAccount) return;
    final epoch = session.coordinator.epoch;
    void current() {
      session.coordinator.requireCurrent(epoch);
      if (session.account != account) throw StateError('帳號已變更');
    }

    Object? failure;
    for (final (kind, key, build) in [
      ('assignments', assignmentsKey, _assignments),
      ('calendar', calendarKey, _calendarDates),
      ('events', eventsKey, _events),
    ]) {
      // A failed read leaves that kind's scheduled reminders as they were.
      try {
        final items = await enabled(key) ? await build() : <CampusNotice>[];
        current();
        await gateway.setNotifications(kind, items);
      } catch (error) {
        failure ??= error;
      }
    }
    // The widgets, class reminders and the in-class notice all read the
    // device copy, so keep it current whenever the timetable is known.
    try {
      current();
      await _saveSchedule();
    } catch (error) {
      failure ??= error;
    }
    if (failure != null) throw failure;
  }

  Future<List<CampusNotice>> _assignments() async {
    final repository = await moodle();
    if (repository == null) throw StateError('請先登入 M 園區');
    final now = clock();
    final limit = now.add(const Duration(days: 14));
    final found = <(DateTime, String, String, String)>[];
    for (final course in await repository.courses()) {
      final name = CoursePresentation(course).title;
      for (final assignment in await repository.assignments(
        number(course['id']),
      )) {
        final seconds = number(assignment['duedate']);
        if (seconds <= 0) continue;
        final due = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
        if (due.isAfter(now) && !due.isAfter(limit)) {
          found.add((
            due,
            '${assignment['id']}',
            '${assignment['name']}',
            name,
          ));
        }
      }
    }
    found.sort((a, b) => a.$1.compareTo(b.$1));
    return [
      for (final (due, id, title, course) in found.take(20))
        if (due.subtract(const Duration(days: 1)).isAfter(now))
          CampusNotice(
            id: id,
            title: '作業即將截止',
            body: '$title（$course）將於 ${_dateTime(due)} 截止',
            at: due.subtract(const Duration(days: 1)),
            link: 'niulife://moodle',
          ),
    ];
  }

  /// Like iOS: only confirmed registrations with a full start date and clock
  /// time; waitlisted, pending or unknown states are left out.
  Future<List<CampusNotice>> _events([List<CampusEvent>? registrations]) async {
    final read = events;
    if (registrations == null && read == null) return const [];
    final list = registrations ?? await read!();
    final lead = Duration(minutes: await eventLead());
    final now = clock();
    final found = <CampusNotice>[];
    for (final event in list) {
      if (!isConfirmedRegistration(event.status) || event.id.isEmpty) continue;
      final start = eventStart(event.time);
      if (start == null) continue;
      final at = start.subtract(lead);
      if (!at.isAfter(now)) continue;
      found.add(
        CampusNotice(
          id: event.id,
          title: '已報名活動即將開始',
          body: '${event.name}（${event.time}）',
          at: at,
          link: 'niulife://events',
        ),
      );
    }
    found.sort((a, b) => a.at.compareTo(b.at));
    return found.take(50).toList();
  }

  static bool isConfirmedRegistration(String status) =>
      ['已報名', '報名成功', '正取', '錄取'].any(status.contains) &&
      !['取消', '停辦', '候補', '備取', '審核', '未'].any(status.contains);

  /// The start of 「2026/10/13 13:30 ~ …」 in Taipei time. A date without a
  /// clock time is unknown, never midnight.
  static DateTime? eventStart(String raw) {
    final m = RegExp(
      r'^(\d{4})[/-](\d{1,2})[/-](\d{1,2})\s*(?:(上午|下午)\s*(\d{1,2})|(\d{2})):(\d{2})(?::(\d{2}))?(?=\s*(?:起|[~～]|$))',
    ).firstMatch(raw.trim());
    if (m == null) return null;
    final year = int.parse(m[1]!), month = int.parse(m[2]!);
    final day = int.parse(m[3]!), minute = int.parse(m[7]!);
    final second = m[8] == null ? 0 : int.parse(m[8]!);
    var hour = int.parse(m[5] ?? m[6]!);
    if (m[4] != null) {
      if (hour < 1 || hour > 12) return null;
      hour = hour % 12 + (m[4] == '下午' ? 12 : 0);
    }
    if (month < 1 || month > 12 || hour > 23 || minute > 59 || second > 59) {
      return null;
    }
    // Taipei is UTC+8 all year.
    final at = DateTime.utc(year, month, day, hour - 8, minute, second);
    final local = at.add(const Duration(hours: 8));
    return local.day == day && local.month == month ? at : null;
  }

  Future<List<CampusNotice>> _calendarDates() async {
    final now = clock();
    final today = CampusDate.at(now);
    final limit = CampusDate.at(now.add(const Duration(days: 30)));
    final events = <CalendarEvent>[];
    for (final year in {today.academicYear, limit.academicYear}) {
      try {
        events.addAll((await calendar.load(year)).events);
      } catch (_) {
        if (year == today.academicYear) rethrow;
      }
    }
    final upcoming =
        events
            .where(
              (e) =>
                  (e.category == 'important' || e.category == 'deadline') &&
                  e.start.compareTo(today) >= 0 &&
                  e.start.compareTo(limit) <= 0,
            )
            .toList()
          ..sort((a, b) => a.start.compareTo(b.start));
    return [
      for (final event in upcoming.take(20))
        // 08:00 in Taipei (UTC+8) on the day before.
        if (DateTime.utc(
          event.start.year,
          event.start.month,
          event.start.day - 1,
        ).isAfter(now))
          CampusNotice(
            id: event.id,
            title: '重要日期提醒',
            body: '${event.title}（${_dateRange(event)}）即將到來',
            at: DateTime.utc(
              event.start.year,
              event.start.month,
              event.start.day - 1,
            ),
            link: 'niulife://calendar',
          ),
    ];
  }

  /// Saves the cached timetable for native class reminders, keeping dates
  /// already chosen on this device.
  Future<void> _saveSchedule({bool requireDates = false}) async {
    final cached = session.cachedSchedule;
    final owner = session.account;
    if (cached == null || owner == null) {
      if (requireDates) throw StateError('請先開啟課表載入一次');
      return;
    }
    final status = await gateway.reminderStatus();
    var start = status.semesterStart, end = status.semesterEnd;
    if (start == null || end == null) {
      final semester = await _currentSemester();
      if (semester == null) {
        if (requireDates) throw StateError('找不到本學期日期');
        return;
      }
      start = '${semester.classesStart}';
      end = '${semester.end}';
    }
    // Offline: keep the snapshot already on the device, if there is one.
    if (!session.isSignedIn) {
      if (status.semesterStart != null || !requireDates) return;
      throw StateError('請連線後再開啟上課提醒');
    }
    await session.saveSchedule(
      ScheduleSnapshot(
        semesterStart: start,
        semesterEnd: end,
        // Custom courses shown this week go to widgets and reminders too.
        blocks: scheduleBlocks(
          ClassSchedule.fromRows(cached.rows).withCustomCourses(
            CustomCourseStore.instance.coursesFor(owner),
            clock().toUtc().add(const Duration(hours: 8)),
          ),
        ),
      ),
      epoch: session.coordinator.epoch,
      owner: owner,
    );
  }

  /// The semester that has not ended yet, from this or the next academic year.
  Future<CalendarSemester?> _currentSemester() async {
    final today = CampusDate.at(clock());
    for (final year in [today.academicYear, today.academicYear + 1]) {
      try {
        for (final semester in (await calendar.load(year)).semesters) {
          if (semester.end.compareTo(today) >= 0) return semester;
        }
      } catch (_) {}
    }
    return null;
  }

  static String _two(int value) => value.toString().padLeft(2, '0');

  static String _dateTime(DateTime instant) {
    final taipei = instant.toUtc().add(const Duration(hours: 8));
    return '${taipei.month}月${taipei.day}日 '
        '${_two(taipei.hour)}:${_two(taipei.minute)}';
  }

  static String _dateRange(CalendarEvent event) {
    String day(CampusDate d) => '${_two(d.month)}/${_two(d.day)}';
    return event.end.compareTo(event.start) == 0
        ? day(event.start)
        : '${day(event.start)}–${day(event.end)}';
  }
}
