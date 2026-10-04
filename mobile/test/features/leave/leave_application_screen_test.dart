import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/core/session/campus_session.dart';
import 'package:niu_mobile/features/leave/leave_application_data.dart';
import 'package:niu_mobile/features/leave/leave_application_screen.dart';
import 'package:niu_mobile/features/leave/leave_application_service.dart';
import 'package:niu_mobile/shared/shared.dart';
import 'leave_application_test.dart' show applicationFixture;
import '../../support/fakes.dart';

class FixtureLeaveGateway implements LeaveApplicationGateway {
  FixtureLeaveGateway({this.notice = false, this.loading});
  bool notice;

  /// Holds [initialize] until completed, like a slow school page.
  Completer<void>? loading;
  bool disposed = false;
  int submits = 0, consents = 0, selections = 0;
  LeaveApplicationData data = LeaveApplicationData.fromJson(
    applicationFixture(),
  );
  @override
  Future<LeaveApplicationData> initialize() async {
    await loading?.future;
    return notice
        ? const LeaveApplicationData(
            revision: 'notice',
            notice: '校方請假注意事項（合成測試資料）',
          )
        : data;
  }

  @override
  Future<LeaveApplicationData> agree(LeaveApplicationData data) async {
    consents++;
    notice = false;
    return this.data;
  }

  @override
  Future<LeaveApplicationData> changeType(
    LeaveApplicationData data,
    String value,
  ) async => this.data;
  @override
  Future<LeaveApplicationData> changeDates(
    LeaveApplicationData data,
    DateTime start,
    DateTime end,
  ) async => this.data;
  @override
  Future<List<LeavePeriodChoice>> periods(LeaveApplicationData data) async => [
    const LeavePeriodChoice(
      value: 'fixture-period',
      date: '115/10/01',
      period: '第一節',
      course: '測試課程',
    ),
  ];
  @override
  Future<LeaveApplicationData> selectPeriods(
    LeaveApplicationData data,
    List<String> values,
  ) async {
    selections++;
    return this.data;
  }

  @override
  Future<void> cancelPeriods() async {}
  @override
  Future<LeaveApplicationData> draft(
    LeaveApplicationData data,
    String reason,
    bool later,
  ) async => this.data = LeaveApplicationData.fromJson({
    ...applicationFixture(),
    'reason': reason,
    'later': later,
  });
  @override
  Future<LeaveApplicationData> attach(
    LeaveApplicationData data,
    String name,
    Uint8List bytes,
  ) async => this.data;
  @override
  Future<LeaveSubmitResult> submit(LeaveApplicationData data) async {
    submits++;
    return const LeaveSubmitResult(message: '尚未確認送出結果');
  }

  @override
  void dispose() {
    disposed = true;
  }
}

void main() {
  late CampusSession session;
  setUp(
    () =>
        session = CampusSession(vault: MemoryVault(), platformCleanup: [])
          ..account = 'b123',
  );
  tearDown(() => session.dispose());
  Future<void> agree(WidgetTester tester) async {
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tester.tap(find.text('同意並開始申請'));
    await tester.pumpAndSettle();
  }

  Widget app(
    FixtureLeaveGateway gateway, {
    bool dark = false,
    double scale = 1,
  }) => MaterialApp(
    theme: dark ? NiuTheme.dark : NiuTheme.light,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(scale),
        padding: const EdgeInsets.only(bottom: 24),
        viewPadding: const EdgeInsets.only(bottom: 24),
      ),
      child: child!,
    ),
    home: LeaveApplicationScreen(session: session, gateway: gateway),
  );
  for (final dark in [false, true]) {
    for (final width in [320.0, 390.0]) {
      testWidgets('native form dark=$dark width=$width large type and IME', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final gateway = FixtureLeaveGateway();
        gateway.data = LeaveApplicationData.fromJson({
          ...applicationFixture(),
          'choices': [
            {'value': '023', 'label': '產假（產前假／陪產假／流產假／哺乳假）'},
            {'value': '003', 'label': '公假'},
          ],
        });
        await tester.pumpWidget(app(gateway, dark: dark, scale: 2));
        await tester.pumpAndSettle();
        await agree(tester);
        expect(find.text('請假內容'), findsOneWidget);
        expect(find.text('公假'), findsNothing);
        // The primary action is pinned below the form.
        expect(tester.takeException(), isNull);
        final action = find.widgetWithText(FilledButton, '確認申請');
        expect(tester.getSize(action).height, greaterThanOrEqualTo(48));
        await tester.scrollUntilVisible(
          find.byType(TextField),
          100,
          scrollable: find
              .descendant(
                of: find.byType(ListView),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.tap(find.byType(TextField));
        await tester.pump();
        tester.view.viewInsets = const FakeViewPadding(bottom: 280);
        await tester.pump();
        expect(tester.takeException(), isNull);
        tester.view.resetViewInsets();
        await tester.pumpWidget(const SizedBox());
        expect(gateway.disposed, isTrue);
      });
    }
  }
  testWidgets('in-app notice needs consent, then agrees on the school page', (
    tester,
  ) async {
    final gateway = FixtureLeaveGateway(notice: true);
    await tester.pumpWidget(app(gateway));
    await tester.pumpAndSettle();
    expect(find.text('請假注意事項'), findsOneWidget);
    expect(find.text('考試週請假'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '同意並開始申請'))
          .onPressed,
      isNull,
    );
    expect(gateway.consents, 0);
    await agree(tester);
    expect(gateway.consents, 1);
    expect(find.text('請假內容'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('consent given while the school loads is sent on arrival', (
    tester,
  ) async {
    final loading = Completer<void>();
    final gateway = FixtureLeaveGateway(notice: true, loading: loading);
    await tester.pumpWidget(app(gateway));
    await tester.pump();
    // The disclaimer leads, and the notice scrolls while the school loads.
    expect(
      tester.getTopLeft(find.text('重要聲明')).dy,
      lessThan(tester.getTopLeft(find.text('請假注意事項')).dy),
    );
    await tester.drag(find.byType(ListView).first, const Offset(0, -2000));
    await tester.pump();
    final list = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byType(ListView).first,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(list.position.pixels, greaterThan(0));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tester.tap(find.text('同意並開始申請'));
    await tester.pump();
    expect(find.text('正在開啟請假表單'), findsOneWidget);
    expect(gateway.consents, 0);
    loading.complete();
    await tester.pumpAndSettle();
    expect(gateway.consents, 1);
    expect(find.text('請假內容'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'submit requires confirmation and unknown result cannot be resent',
    (tester) async {
      final gateway = FixtureLeaveGateway();
      await tester.pumpWidget(app(gateway));
      await tester.pumpAndSettle();
      await agree(tester);
      await tester.scrollUntilVisible(
        find.text('確認申請'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('確認申請'));
      await tester.pumpAndSettle();
      expect(gateway.submits, 0);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(gateway.submits, 0);
      await tester.tap(find.text('確認申請'));
      await tester.pumpAndSettle();
      expect(find.text('確認送出請假'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '送出申請'));
      await tester.pumpAndSettle();
      expect(gateway.submits, 1);
      expect(find.text('確認申請'), findsNothing);
      expect(find.text('請確認送出結果'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('logout clears visible identity-bound draft', (tester) async {
    final gateway = FixtureLeaveGateway();
    await tester.pumpWidget(app(gateway));
    await tester.pumpAndSettle();
    await agree(tester);
    await tester.runAsync(() => session.logout());
    await tester.pumpAndSettle();
    expect(find.text('請假內容'), findsNothing);
    expect(find.text('已登出，請重新開啟申請'), findsOneWidget);
    expect(gateway.disposed, isTrue);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('unsent draft requires confirmation before Android back', (
    tester,
  ) async {
    final gateway = FixtureLeaveGateway();
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: nav,
        theme: NiuTheme.light,
        home: const Scaffold(body: Text('請假紀錄')),
      ),
    );
    nav.currentState!.push(
      MaterialPageRoute<bool>(
        builder: (_) =>
            LeaveApplicationScreen(session: session, gateway: gateway),
      ),
    );
    await tester.pumpAndSettle();
    await agree(tester);
    await tester.scrollUntilVisible(
      find.byType(TextField),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(find.byType(TextField), '尚未送出的原因');
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('離開申請？'), findsOneWidget);
    expect(gateway.submits, 0);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.byType(LeaveApplicationScreen), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '確認'));
    await tester.pumpAndSettle();
    expect(find.byType(LeaveApplicationScreen), findsNothing);
    expect(gateway.disposed, isTrue);
  });
}
