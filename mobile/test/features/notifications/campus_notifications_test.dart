import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/core/platform/schedule_gateway.dart';
import 'package:niu_mobile/core/session/campus_session.dart';
import 'package:niu_mobile/features/academic_calendar/calendar_repository.dart';
import 'package:niu_mobile/features/events/event_models.dart';
import 'package:niu_mobile/features/moodle/moodle_demo.dart';
import 'package:niu_mobile/features/notifications/campus_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late CampusSession session;
  late FakeGateway gateway;

  // What reached the native schedule channel (the device timetable copy).
  final native = <String>[];
  setUp(() async {
    session = CampusSession(vault: MemoryVault(), platformCleanup: []);
    await session.enterDemo();
    gateway = FakeGateway();
    native.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ScheduleGateway.channel, (call) async {
          native.add(call.method);
          return null;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ScheduleGateway.channel, null),
  );
  tearDown(() => session.dispose());

  CampusNotifications notifications({
    DateTime Function()? clock,
    Future<List<CampusEvent>> Function()? events,
  }) => CampusNotifications(
    session: session,
    moodle: () async => DemoMoodleRepository()..bindSession(session),
    calendar: BundledCalendarRepository(rootBundle),
    gateway: gateway,
    clock: clock,
    events: events,
  );

  CampusEvent registered(String id, String status, String time) =>
      CampusEvent.fromJson({
        'id': id,
        'name': '活動 $id',
        'status': status,
        'time': time,
      });

  test('event reminders: confirmed registrations with a clock time', () async {
    SharedPreferences.setMockInitialValues({
      CampusNotifications.eventsKey: true,
      CampusNotifications.eventLeadKey: 60,
    });
    final now = DateTime.utc(2026, 10, 10, 4); // 12:00 Taipei.
    await notifications(
      clock: () => now,
      events: () async => [
        registered('1', '報名成功', '2026/10/12 13:30 ~ 2026/10/12 16:00'),
        registered('2', '候補', '2026/10/12 13:30'),
        registered('3', '已報名', '2026/10/12'), // No clock time.
        registered('4', '已報名', '2026/10/10 12:30'), // Lead already passed.
        registered('5', '報名取消', '2026/10/12 13:30'),
        registered('6', '錄取', '2026/10/11 下午 2:00'),
      ],
    ).refresh();
    final items = gateway.sent['events']!;
    expect([for (final i in items) i.id], ['6', '1']);
    expect(items[1].at, DateTime.utc(2026, 10, 12, 4, 30));
    expect(items[0].at, DateTime.utc(2026, 10, 11, 5));
    expect(items[1].title, '已報名活動即將開始');
    expect(items[1].link, 'niulife://events');
  });

  test('a registration change updates event reminders alone', () async {
    SharedPreferences.setMockInitialValues({
      CampusNotifications.eventsKey: true,
    });
    var reads = 0;
    final now = DateTime.utc(2026, 10, 10, 4);
    final reminders = notifications(
      clock: () => now,
      events: () async {
        reads++;
        return [registered('7', '報名成功', '2026/10/20 09:00')];
      },
    );
    // The screen's fresh list is used as is.
    await reminders.refreshEvents([
      registered('8', '報名成功', '2026/10/21 09:00'),
    ]);
    expect([for (final i in gateway.sent['events']!) i.id], ['8']);
    expect(reads, 0);
    expect(gateway.sent.keys, ['events']);
    // Without one, 我的報名 is read again.
    await reminders.refreshEvents();
    expect([for (final i in gateway.sent['events']!) i.id], ['7']);
    expect(reads, 1);
  });

  test('a failed read keeps the scheduled event reminders', () async {
    SharedPreferences.setMockInitialValues({
      CampusNotifications.eventsKey: true,
    });
    await expectLater(
      notifications(events: () async => throw StateError('offline')).refresh(),
      throwsStateError,
    );
    expect(gateway.sent.containsKey('events'), isFalse);
  });

  test('disabled kinds clear their pending notifications', () async {
    SharedPreferences.setMockInitialValues({});
    await notifications().refresh();
    expect(gateway.sent['assignments'], isEmpty);
    expect(gateway.sent['calendar'], isEmpty);
  });

  test(
    'assignment deadlines fire a day early, past ones are skipped',
    () async {
      SharedPreferences.setMockInitialValues({
        CampusNotifications.assignmentsKey: true,
      });
      await notifications().refresh();
      final items = gateway.sent['assignments']!;
      expect(items, isNotEmpty);
      for (final item in items) {
        expect(item.title, '作業即將截止');
        expect(item.body, contains('截止'));
        expect(item.at.isAfter(DateTime.now()), isTrue);
        expect(item.link, 'niulife://moodle');
      }
    },
  );

  test(
    'important calendar dates fire at 08:00 Taipei the day before',
    () async {
      SharedPreferences.setMockInitialValues({
        CampusNotifications.calendarKey: true,
      });
      final now = DateTime.utc(2026, 10, 1, 3);
      await notifications(clock: () => now).refresh();
      final items = gateway.sent['calendar']!;
      expect(items, isNotEmpty);
      expect(items.length, lessThanOrEqualTo(20));
      for (final item in items) {
        expect(item.title, '重要日期提醒');
        expect(item.body, endsWith('即將到來'));
        expect(
          item.at.isUtc && item.at.hour == 0 && item.at.minute == 0,
          isTrue,
        );
        expect(item.at.isAfter(now), isTrue);
        expect(item.at.isBefore(now.add(const Duration(days: 30))), isTrue);
      }
    },
  );

  test('the calendar provides the current teaching span', () async {
    final snapshot = await BundledCalendarRepository(rootBundle).load(115);
    expect(snapshot.semesters.first.classesStart.toString(), '2026-09-07');
    expect(snapshot.semesters.first.end.toString(), '2027-01-31');
  });

  test('the in-class notice saves the timetable before switching on', () async {
    SharedPreferences.setMockInitialValues({});
    final clock = DateTime(2026, 10, 2, 9, 30);
    await notifications(clock: () => clock).setClassNow(true);
    expect(native, contains('saveSnapshot'));
    expect(gateway.classNow, isTrue);

    gateway.permitted = false;
    await expectLater(
      notifications(clock: () => clock).setClassNow(true),
      throwsStateError,
    );
    await notifications().setClassNow(false);
    expect(gateway.classNow, isFalse);
  });

  test('the timetable reaches the device even with reminders off', () async {
    // The home-screen widgets read the device copy.
    SharedPreferences.setMockInitialValues({});
    final clock = DateTime(2026, 10, 2, 9, 30);
    await notifications(clock: () => clock).refresh();
    expect(native, contains('saveSnapshot'));
  });
}
