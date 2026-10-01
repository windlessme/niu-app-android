import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:niu_mobile/core/demo/demo_account.dart';
import 'package:niu_mobile/core/demo/demo_data.dart';
import 'package:niu_mobile/core/session/campus_session.dart';
import 'package:niu_mobile/core/web/academic_portal_screen.dart';
import 'package:niu_mobile/features/attendance/attendance_repository.dart';
import 'package:niu_mobile/features/authentication/login_screen.dart';
import 'package:niu_mobile/features/demo/demo_services.dart';
import 'package:niu_mobile/features/events/events_screen.dart';
import 'package:niu_mobile/features/graduation/graduation_screen.dart';
import 'package:niu_mobile/features/grades/grades_screen.dart';
import 'package:niu_mobile/features/leave/leave_application_data.dart';
import 'package:niu_mobile/features/postal/postal_models.dart';
import 'package:niu_mobile/features/registration/certificate_service.dart';
import 'package:niu_mobile/features/registration/registration_data.dart';
import 'package:niu_mobile/features/schedule/schedule_screen.dart';
import 'package:niu_mobile/shared/shared.dart';
import 'features/authentication_session_test.dart' show MemoryVault;

void main() {
  test('only the exact review credentials enter the demo', () {
    expect(isDemoLogin('niulifedemo', 'x9Ru-ZeuT-pXnq'), isTrue);
    expect(isDemoLogin(' NIULIFEDEMO ', 'x9Ru-ZeuT-pXnq'), isTrue);
    expect(isDemoLogin('niulifedemo', 'x9ru-zeut-pxnq'), isFalse);
    expect(isDemoLogin('b1234567', 'x9Ru-ZeuT-pXnq'), isFalse);
  });

  test(
    'demo session survives restart without the school and clears on logout',
    () async {
      final vault = MemoryVault();
      final session = CampusSession(vault: vault, platformCleanup: []);
      await session.enterDemo();
      expect(session.isDemo, isTrue);
      expect(session.isSignedIn, isTrue);
      expect(session.account, demoAccount);
      expect(session.cachedSchedule?.rows, isNotEmpty);
      await expectLater(session.academicEntry(), throwsStateError);

      final restored = CampusSession(vault: vault, platformCleanup: []);
      await restored.restore();
      expect(restored.isDemo, isTrue);
      expect(restored.displayName, '示範同學');

      await restored.logout();
      expect(restored.isDemo, isFalse);
      expect(vault.values['ssoToken'], isNull);
      session.dispose();
      restored.dispose();
    },
  );

  testWidgets('demo credentials sign in without the school login page', (
    tester,
  ) async {
    final session = CampusSession(vault: MemoryVault(), platformCleanup: []);
    addTearDown(session.dispose);
    var signedIn = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: NiuTheme.light,
        home: LoginScreen(session: session, onSignedIn: () => signedIn = true),
      ),
    );
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'niulifedemo');
    await tester.enterText(fields.at(1), 'x9Ru-ZeuT-pXnq');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '登入'));
    // The app leaves the login page on success; this test stays on it.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(signedIn, isTrue);
    expect(find.byType(InAppWebView), findsNothing);
    expect(session.isDemo, isTrue);
  });

  test('every school page sample parses with the real parsers', () {
    final schedule = ClassSchedule.fromRows(DemoData.scheduleRows);
    expect(schedule.days, hasLength(5));
    expect(schedule.periods.any((p) => p.courses.isNotEmpty), isTrue);
    final history = GradeCourse.parseHistoryRows([
      for (final r in DemoData.grades('history')['rows'] as List)
        (r as List).cast<String>(),
    ]);
    expect(history, isNotEmpty);
    expect(GradeMode.values.map((m) => DemoData.grades(m.name)), hasLength(3));
    expect(GraduationData.fromJson(DemoData.graduation).credits, isNotEmpty);
    expect(
      RegistrationData.fromJson(
        DemoData.registration(demoAccount),
      ).belongsTo(demoAccount),
      isTrue,
    );
    expect(DemoData.leaveList['records'], isNotEmpty);
    expect(DemoData.leaveDetail('D1150915')['workflow'], hasLength(2));
  });

  testWidgets('school pages show demo data and never create a WebView', (
    tester,
  ) async {
    final session = CampusSession(vault: MemoryVault(), platformCleanup: []);
    addTearDown(session.dispose);
    await session.enterDemo();
    await tester.pumpWidget(
      MaterialApp(
        theme: NiuTheme.light,
        home: AcademicPortalScreen(
          title: '畢業門檻',
          session: session,
          target: Uri.parse('https://acade.niu.edu.tw/'),
          extractScript: 'null',
          webViewBuilder: (_) => throw StateError('WebView in demo'),
          demoSnapshot: () => DemoData.graduation,
          snapshotBuilder: (_, value) =>
              Text('credits ${(value as Map)['creditRequired']}'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('credits [128, 82]'), findsOneWidget);
    expect(find.byTooltip('查看學校網頁'), findsNothing);

    await tester.pumpWidget(
      MaterialApp(
        theme: NiuTheme.light,
        home: AcademicPortalScreen(
          key: const ValueKey('other'),
          title: '其他',
          session: session,
          target: Uri.parse('https://acade.niu.edu.tw/'),
          extractScript: 'null',
          webViewBuilder: (_) => throw StateError('WebView in demo'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('示範模式沒有提供'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('M 園區 demo answers every screen and attendance records', () async {
    final moodle = DemoMoodleRepository();
    final courses = await moodle.courses();
    expect(courses, hasLength(8));
    final id = courses.first['id'] as int;
    expect(await moodle.contents(id), isNotEmpty);
    expect(await moodle.announcements(id), isNotEmpty);
    expect(await moodle.posts(id * 100 + 1), hasLength(2));
    final assignments = await moodle.assignments(id);
    expect(assignments, hasLength(2));
    final status = await moodle.submission(assignments.last['id'] as int);
    expect(status['lastattempt']['submission']['status'], 'submitted');
    expect(await moodle.grades(id), isNotEmpty);
    expect(await moodle.notifications(), isNotEmpty);
    await moodle.uploadFiles(assignments.first['id'] as int, [
      (name: 'a.pdf', bytes: [1]),
    ]);
    await moodle.submit(assignments.first['id'] as int, acceptStatement: true);
    final pdf = await moodle.download('https://euni.niu.edu.tw/x/syllabus.pdf');
    expect(isCertificatePdf(200, 'application/pdf', pdf), isTrue);
    final attendance = await AttendanceRepository(moodle).course(id);
    expect(attendance.single.present, 2);
    expect(attendance.single.late, 1);
    expect(attendanceQr(demoAttendanceLink), isNotNull);
  });

  test('leave application is simulated end to end', () async {
    final gateway = DemoLeaveGateway();
    final notice = await gateway.initialize();
    expect(notice.notice, isNotNull);
    var form = await gateway.agree(notice);
    final monday = DateTime.now().add(
      Duration(days: 8 - DateTime.now().weekday),
    );
    form = await gateway.changeDates(form, monday, monday);
    final periods = await gateway.periods(form);
    expect(periods.map((p) => p.course), contains('資料結構'));
    form = await gateway.selectPeriods(form, [periods.first.value]);
    form = await gateway.draft(form, '家中有事', false);
    expect(form.validate(form.reason), isNull);
    expect(form.total, '1');
    final result = await gateway.submit(form);
    expect(result.confirmed, isTrue);
    expect(result.message, contains('示範模式'));
    expect(parseSchoolLeaveDate(form.start), isNotNull);
  });

  test('event registration moves between lists', () async {
    final actions = DemoEventActions();
    final event = CampusEvent.fromJson(DemoEvents.list(applied: false).first);
    expect(event.canApply, isTrue);
    expect((await actions.register(event)).success, isTrue);
    expect(
      DemoEvents.list(applied: true).map((e) => e['id']),
      contains(event.id),
    );
    expect(
      DemoEvents.list(applied: false).map((e) => e['id']),
      isNot(contains(event.id)),
    );
    expect((await actions.cancel(event)).success, isTrue);
    expect(event.credits.single.category, isNotEmpty);
  });

  test('postal demo answers each status', () async {
    final service = DemoPostalService();
    final waiting = await service.search(
      const PostalQuery(name: '示範同學', status: PostalStatus.waiting),
    );
    expect(waiting.records.single.trackingNumber, 'RR123456789TW');
    final returned = await service.search(
      const PostalQuery(name: '示範同學', status: PostalStatus.returned),
    );
    expect(returned.records, isEmpty);
  });
}
