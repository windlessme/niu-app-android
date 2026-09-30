import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/core/session/cached_graduation.dart';
import 'package:niu_mobile/core/web/academic_portal_screen.dart';
import 'package:niu_mobile/features/graduation/graduation_screen.dart';
import 'package:niu_mobile/features/graduation/graduation_dashboard.dart';
import 'package:niu_mobile/shared/shared.dart';

import 'features/authentication_session_test.dart' show MemoryVault;
import 'schedule_screen_test.dart' show ScheduleSession;
import 'graduation_cache_test.dart' show graduationFixture;

void main() {
  late ScheduleSession session;
  late MemoryVault vault;
  final fetchedAt = DateTime.utc(2026, 9, 20, 8, 30);
  setUp(() {
    vault = MemoryVault();
    session = ScheduleSession(vault)
      ..account = 'b123'
      ..cachedGraduation = CachedGraduation(
        account: 'b123',
        fetchedAt: fetchedAt,
        data: graduationFixture(),
      );
  });
  tearDown(() => session.dispose());

  Widget app({bool dark = false, double scale = 1}) => MaterialApp(
    theme: dark ? NiuTheme.dark : NiuTheme.light,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: GraduationScreen(
      session: session,
      webViewBuilder: (_) => const SizedBox.expand(),
    ),
  );

  for (final offline in [false, true]) {
    for (final dark in [false, true]) {
      testWidgets(
        'cache opens repeatedly without network offline=$offline dark=$dark at 320/2',
        (tester) async {
          tester.view.physicalSize = const Size(320, 568);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          session.isOffline = offline;
          for (var i = 0; i < 2; i++) {
            await tester.pumpWidget(app(dark: dark, scale: 2));
            expect(find.byType(GraduationDashboard), findsOneWidget);
            expect(find.byType(NiuSyncStatus), findsOneWidget);
            expect(find.byType(AcademicPortalScreen), findsNothing);
            await tester.pump(const Duration(seconds: 2));
            expect(session.portalRequests, 0);
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox());
          }
        },
      );
    }
  }

  testWidgets(
    'first success persists data and subsequent opening skips school',
    (tester) async {
      session.cachedGraduation = null;
      await tester.pumpWidget(app());
      await tester.pump();
      expect(session.portalRequests, 1);
      final portal = tester.widget<AcademicPortalScreen>(
        find.byType(AcademicPortalScreen),
      );
      await portal.onSnapshot!(graduationFixture(), 0);
      await tester.pump();
      expect(find.byType(GraduationDashboard), findsOneWidget);
      expect(vault.values['graduationCache'], isNotNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(app());
      expect(find.byType(AcademicPortalScreen), findsNothing);
      expect(session.portalRequests, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('manual refresh updates cache and closes only its query route', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.tap(find.byTooltip('更新畢業門檻'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(session.portalRequests, 1);
    final portal = tester.widget<AcademicPortalScreen>(
      find.byType(AcademicPortalScreen),
    );
    await portal.onSnapshot!(graduationFixture(english: '最新結果'), 0);
    await tester.pumpAndSettle();
    expect(find.byType(AcademicPortalScreen), findsNothing);
    final dashboard = tester.widget<GraduationDashboard>(
      find.byType(GraduationDashboard),
    );
    expect(dashboard.data.english, '最新結果');
    expect(dashboard.updatedAt!.isAfter(fetchedAt), isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('refresh timeout and Android back retain previous data', (
    tester,
  ) async {
    final cached = session.cachedGraduation;
    await tester.pumpWidget(app());
    await tester.tap(find.byTooltip('更新畢業門檻'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 61));
    expect(find.text('學校系統回應逾時。可以再試一次，或直接開啟學校網頁。'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(GraduationDashboard), findsOneWidget);
    expect(session.cachedGraduation, same(cached));
    expect(vault.values['graduationCache'], isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('wrong-account cache and logout never expose previous data', (
    tester,
  ) async {
    session.account = 'b456';
    await tester.pumpWidget(app());
    await tester.pump();
    expect(find.byType(GraduationDashboard), findsNothing);
    final portal = tester.widget<AcademicPortalScreen>(
      find.byType(AcademicPortalScreen),
    );
    await tester.runAsync(() => session.logout());
    await tester.pump();
    expect(find.byType(GraduationDashboard), findsNothing);
    await expectLater(
      portal.onSnapshot!(graduationFixture(), 0),
      throwsException,
    );
    expect(session.cachedGraduation, isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
