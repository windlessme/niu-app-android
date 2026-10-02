import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/core/platform/schedule_gateway.dart';
import 'package:niu_mobile/core/session/campus_session.dart';
import 'package:niu_mobile/features/academic_calendar/calendar_repository.dart';
import 'package:niu_mobile/features/demo/demo_services.dart';
import 'package:niu_mobile/features/notifications/campus_notifications.dart';
import 'package:niu_mobile/features/notifications/notification_settings_screen.dart';
import 'package:niu_mobile/shared/shared.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'campus_notifications_test.dart' show FakeGateway;
import 'features/authentication_session_test.dart' show MemoryVault;

class _PermittedGateway extends FakeGateway {
  @override
  Future<bool> requestNotificationPermission() async => true;
}

void main() {
  testWidgets('tapping a row, not only its switch, toggles the setting', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      ScheduleGateway.channel,
      (_) async => null,
    );
    final session = CampusSession(vault: MemoryVault(), platformCleanup: []);
    await session.enterDemo();
    addTearDown(session.dispose);
    final gateway = _PermittedGateway();
    final notifications = CampusNotifications(
      session: session,
      moodle: () async => DemoMoodleRepository()..bindSession(session),
      calendar: BundledCalendarRepository(rootBundle),
      gateway: gateway,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: NiuTheme.light,
        home: NotificationSettingsScreen(
          notifications: notifications,
          gateway: gateway,
        ),
      ),
    );
    await tester.pumpAndSettle();
    Switch toggle() => tester.widget<Switch>(
      find.descendant(
        of: find.widgetWithText(NiuRow, '作業死線通知'),
        matching: find.byType(Switch),
      ),
    );
    expect(toggle().value, isFalse);

    await tester.tap(find.text('作業死線通知'));
    await tester.pumpAndSettle();
    expect(toggle().value, isTrue);
    expect(
      await notifications.enabled(CampusNotifications.assignmentsKey),
      isTrue,
    );

    await tester.tap(find.text('M 園區作業截止前一天提醒'));
    await tester.pumpAndSettle();
    expect(toggle().value, isFalse);
  });
}
