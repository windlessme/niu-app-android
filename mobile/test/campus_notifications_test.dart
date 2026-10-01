import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/core/platform/schedule_gateway.dart';
import 'package:niu_mobile/core/session/campus_session.dart';
import 'package:niu_mobile/features/academic_calendar/calendar_repository.dart';
import 'package:niu_mobile/features/demo/demo_services.dart';
import 'package:niu_mobile/features/notifications/campus_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'features/authentication_session_test.dart' show MemoryVault;

class FakeGateway extends ScheduleGateway {
  final sent = <String, List<CampusNotice>>{};
  @override
  Future<void> setNotifications(String kind, List<CampusNotice> items) async =>
      sent[kind] = items;
  @override
  Future<ReminderStatus> reminderStatus() async =>
      const ReminderStatus(enabled: false, permitted: true);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late CampusSession session;
  late FakeGateway gateway;

  setUp(() async {
    session = CampusSession(vault: MemoryVault(), platformCleanup: []);
    await session.enterDemo();
    gateway = FakeGateway();
  });
  tearDown(() => session.dispose());

  CampusNotifications notifications({DateTime Function()? clock}) =>
      CampusNotifications(
        session: session,
        moodle: () async => DemoMoodleRepository()..bindSession(session),
        calendar: BundledCalendarRepository(rootBundle),
        gateway: gateway,
        clock: clock,
      );

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
}
