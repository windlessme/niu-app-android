import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/core/session/cached_schedule.dart';
import 'package:niu_mobile/core/session/campus_session.dart';
import 'package:niu_mobile/core/web/academic_portal_screen.dart';
import 'package:niu_mobile/features/schedule/schedule_export.dart';
import 'package:niu_mobile/features/schedule/schedule_screen.dart';

import 'features/authentication_session_test.dart' show MemoryVault;

List<List<String>> rows(String course) => [
  ['節次', '時間', '星期一', '星期二', '星期三', '星期四', '星期五'],
  ['1', '08:10~09:00', course, course, course, course, course],
];

class ScheduleSession extends CampusSession {
  ScheduleSession(MemoryVault vault) : super(vault: vault, platformCleanup: []);
  int portalRequests = 0;

  @override
  bool get isSignedIn => account != null && !isOffline;

  @override
  Future<Uri> academicEntry() async {
    portalRequests++;
    return Uri.parse('https://acade.niu.edu.tw/NIU/MainFrame.aspx');
  }
}

void main() {
  late MemoryVault vault;
  late ScheduleSession session;
  late int webViews;
  final fetchedAt = DateTime.utc(2026, 9, 20, 8, 30);

  setUp(() {
    vault = MemoryVault();
    session = ScheduleSession(vault)
      ..account = 'b123'
      ..cachedSchedule = CachedSchedule(
        account: 'b123',
        fetchedAt: fetchedAt,
        rows: rows('已存課程'),
      );
    webViews = 0;
  });

  Widget app() => MaterialApp(
    home: ScheduleScreen(
      session: session,
      webViewBuilder: (_) {
        webViews++;
        return const SizedBox(key: Key('school-webview'));
      },
    ),
  );

  for (final offline in [false, true]) {
    testWidgets('cache opens immediately every time (offline: $offline)', (
      tester,
    ) async {
      session.isOffline = offline;
      for (var open = 0; open < 2; open++) {
        await tester.pumpWidget(app());
        expect(find.byType(ScheduleView), findsOneWidget);
        expect(find.byType(ScheduleExportBar), findsNothing);
        expect(find.textContaining('帳號 b123'), findsNothing);
        expect(
          find.textContaining('$fetchedAt'.split(' ').first),
          findsNothing,
        );
        expect(find.byTooltip('更新課表'), findsOneWidget);
        expect(find.byType(AcademicPortalScreen), findsNothing);
        expect(find.byType(InAppWebView), findsNothing);
        await tester.pump(const Duration(seconds: 2));
        expect(session.portalRequests, 0);
        expect(webViews, 0);
        await tester.pumpWidget(const SizedBox());
      }
      session.dispose();
    });
  }

  testWidgets(
    'manual refresh persists school snapshot then shows native cache',
    (tester) async {
      await tester.pumpWidget(app());
      await tester.tap(find.byTooltip('更新課表'));
      await tester.pump();
      await tester.pump();
      expect(session.portalRequests, 1);
      expect(webViews, greaterThan(0));
      final portal = tester.widget<AcademicPortalScreen>(
        find.byType(AcademicPortalScreen),
      );
      final updated = rows('更新課程');
      await portal.onSnapshot!(updated, session.coordinator.epoch);
      expect(jsonDecode(vault.values['scheduleCache']!)['rows'], updated);
      expect(session.cachedSchedule!.fetchedAt.isAfter(fetchedAt), isTrue);
      await tester.pump();
      expect(find.byType(AcademicPortalScreen), findsNothing);
      expect(find.byKey(const Key('school-webview')), findsNothing);
      final native = tester.widget<ScheduleView>(find.byType(ScheduleView));
      expect(native.schedule.periods.first.courses['星期一'], '更新課程');
      expect(find.byType(ScheduleExportBar), findsNothing);
      expect(
        find.textContaining('${session.cachedSchedule!.fetchedAt.toLocal()}'),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(app());
      expect(find.byType(ScheduleView), findsOneWidget);
      expect(session.portalRequests, 1);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );

  testWidgets('another account cache is never displayed or overwritten', (
    tester,
  ) async {
    session.account = 'b456';
    await tester.pumpWidget(app());
    await tester.pump();
    expect(find.byType(ScheduleView), findsNothing);
    expect(find.textContaining('帳號 b123'), findsNothing);
    final portal = tester.widget<AcademicPortalScreen>(
      find.byType(AcademicPortalScreen),
    );
    session.account = 'b789';
    await expectLater(
      portal.onSnapshot!(rows('舊帳號課程'), session.coordinator.epoch),
      throwsException,
    );
    expect(vault.values['scheduleCache'], isNull);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });

  testWidgets(
    'options sheet contains export controls; reminders live in settings',
    (tester) async {
      await tester.pumpWidget(app());
      await tester.tap(find.byTooltip('課表選項'));
      await tester.pumpAndSettle();
      expect(find.byType(ScheduleExportBar), findsOneWidget);
      expect(find.byTooltip('匯出行事曆'), findsOneWidget);
      expect(find.text('上課前 10 分鐘提醒'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );

  testWidgets('manual refresh can return to existing cache', (tester) async {
    await tester.pumpWidget(app());
    await tester.tap(find.byTooltip('更新課表'));
    await tester.pump();
    await tester.tap(find.text('先看已保存的課表'));
    await tester.pump();
    expect(find.byType(ScheduleView), findsOneWidget);
    expect(find.byType(AcademicPortalScreen), findsNothing);
    expect(session.cachedSchedule!.rows, rows('已存課程'));
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });

  testWidgets('without cache opens the school portal', (tester) async {
    session.cachedSchedule = null;
    await tester.pumpWidget(app());
    await tester.pump();
    expect(find.byType(AcademicPortalScreen), findsOneWidget);
    expect(find.byType(ScheduleView), findsNothing);
    expect(session.portalRequests, 1);
    expect(webViews, greaterThan(0));
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });

  testWidgets('logout removes visible cached schedule', (tester) async {
    await tester.pumpWidget(app());
    expect(find.byType(ScheduleView), findsOneWidget);
    await tester.runAsync(() => session.logout());
    await tester.pump();
    expect(find.byType(ScheduleView), findsNothing);
    expect(find.textContaining('帳號 b123'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });
}
