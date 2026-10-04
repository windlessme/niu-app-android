import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/core/session/campus_session.dart';
import 'package:niu_mobile/core/session/session_coordinator.dart';
import 'package:niu_mobile/features/academic_portal/academic_portal_screen.dart';
import 'package:niu_mobile/shared/shared.dart';

import 'features/authentication_session_test.dart' show MemoryVault;
import 'fresh_academic_session_test.dart' show FreshSso;

final target = Uri.parse(
  'https://acade.niu.edu.tw/NIU/Application/ENR/ENR50/ENR5020_01.aspx',
);
final expired = WebUri('https://acade.niu.edu.tw/NIU/TimeOutPage.aspx');

class CountingSso extends FreshSso {
  int bridges = 0;
  @override
  Future<Uri> academicEntry(String token, String account) {
    bridges++;
    return super.academicEntry(token, account);
  }
}

class PortalController extends Fake implements InAppWebViewController {
  final replies = Queue<Object?>();
  final loaded = <URLRequest>[];
  int evaluations = 0;
  Completer<Object?>? pending;

  @override
  Future<dynamic> evaluateJavascript({
    required String source,
    ContentWorld? contentWorld,
  }) async {
    evaluations++;
    if (pending != null) return pending!.future;
    return replies.isEmpty ? null : replies.removeFirst();
  }

  @override
  Future<void> loadUrl({
    required URLRequest urlRequest,
    Uri? iosAllowingReadAccessTo,
    WebUri? allowingReadAccessTo,
  }) async => loaded.add(urlRequest);

  @override
  Future<void> stopLoading() async {}
}

void main() {
  testWidgets(
    'reuse skips GUID, expiry reconnects once and then requests login',
    (tester) async {
      final api = CountingSso();
      final session = CampusSession(vault: MemoryVault(), sso: api);
      await tester.runAsync(() => session.acceptToken('fixture', 'b123'));
      session.confirmAcademicSession(session.coordinator.epoch);
      await tester.pumpWidget(
        MaterialApp(
          home: AcademicPortalScreen(
            title: '註冊資訊',
            session: session,
            target: target,
            extractScript: 'null',
            webViewBuilder: (_) => const SizedBox.expand(),
          ),
        ),
      );
      await tester.pump();
      final dynamic state = tester.state(find.byType(AcademicPortalScreen));
      expect(state.entry, target);
      expect(api.bridges, 0);
      final web = PortalController();
      state.controller = web;
      await state.loaded(web, expired);
      expect(api.bridges, 1);
      expect(web.loaded.single.url!.path, '/NIU/Login.aspx');
      expect(session.hasAcademicSession, isFalse);
      await state.loaded(web, expired);
      await tester.pump();
      expect(api.bridges, 1);
      expect(find.text('校務登入已過期，請重新登入。'), findsOneWidget);
      expect(find.text('重新登入'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    },
  );

  testWidgets('a verified snapshot enables reuse and logout invalidates it', (
    tester,
  ) async {
    final api = CountingSso();
    final session = CampusSession(vault: MemoryVault(), sso: api);
    await tester.runAsync(() => session.acceptToken('fixture', 'b123'));
    await tester.pumpWidget(
      MaterialApp(
        home: AcademicPortalScreen(
          title: '畢業門檻',
          session: session,
          target: target,
          extractScript: 'JSON.stringify({})',
          snapshotBuilder: (_, _) => const Text('已取得資料'),
          webViewBuilder: (_) => const SizedBox.expand(),
        ),
      ),
    );
    await tester.pump();
    expect(api.bridges, 1);
    expect(session.hasAcademicSession, isFalse);
    final dynamic state = tester.state(find.byType(AcademicPortalScreen));
    final web = PortalController()
      ..replies.addAll([
        'ready',
        jsonEncode({'signature': 'document-1', 'value': '{}'}),
        'document-1',
      ]);
    state.controller = web;
    await state.poll();
    await tester.pump();
    expect(find.text('已取得資料'), findsOneWidget);
    expect(session.hasAcademicSession, isTrue);
    final epoch = session.coordinator.epoch;
    await tester.runAsync(() => session.coordinator.logout(() async {}));
    expect(session.hasAcademicSession, isFalse);
    expect(
      () => session.confirmAcademicSession(epoch),
      throwsA(isA<SessionChanged>()),
    );
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });

  testWidgets('challenge reveals the same WebView and resumes native content', (
    tester,
  ) async {
    const host = Key('school-host');
    await tester.pumpWidget(
      MaterialApp(
        home: AcademicPortalScreen(
          title: '註冊資訊',
          bridge: false,
          target: target,
          navigationScript: 'fixture-navigation',
          extractScript: 'fixture-extraction',
          snapshotBuilder: (_, _) => const Text('已取得資料'),
          loadTimeout: const Duration(seconds: 2),
          webViewBuilder: (_) => const SizedBox.expand(key: host),
        ),
      ),
    );
    await tester.pump();
    final original = tester.element(find.byKey(host));
    final dynamic state = tester.state(find.byType(AcademicPortalScreen));
    final web = PortalController()..replies.add('interaction-required');
    state.controller = web;
    await state.poll();
    await tester.pump();
    expect(find.text('請在學校網頁完成驗證或登入，完成後會自動繼續。'), findsOneWidget);
    expect(find.byType(NiuLoading), findsNothing);
    expect(tester.element(find.byKey(host)), same(original));
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('學校系統回應逾時。可以再試一次，或直接開啟學校網頁。'), findsNothing);
    web.replies.addAll([
      'ready',
      jsonEncode({'signature': 'verified', 'value': '{}'}),
      'verified',
    ]);
    await state.poll();
    await tester.pump();
    expect(find.text('已取得資料'), findsOneWidget);
    expect(find.text('請在學校網頁完成驗證或登入，完成後會自動繼續。'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'polling pauses off-route and in background without duplicate work',
    (tester) async {
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          home: AcademicPortalScreen(
            title: '註冊資訊',
            bridge: false,
            target: target,
            extractScript: 'null',
            loadTimeout: const Duration(seconds: 3),
            webViewBuilder: (_) => const SizedBox.expand(),
          ),
        ),
      );
      await tester.pump();
      final dynamic state = tester.state(find.byType(AcademicPortalScreen));
      final web = PortalController()..pending = Completer<Object?>();
      state.controller = web;
      final Future<void> first = state.poll();
      await state.poll();
      expect(web.evaluations, 1);
      web.pending!.complete(null);
      await first;
      web.pending = null;
      navigator.currentState!.push<void>(
        MaterialPageRoute(builder: (_) => const Scaffold(body: Text('其他頁面'))),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final before = web.evaluations;
      await tester.pump(const Duration(seconds: 5));
      expect(web.evaluations, before);
      navigator.currentState!.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('學校系統回應逾時。可以再試一次，或直接開啟學校網頁。'), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      final paused = web.evaluations;
      await tester.pump(const Duration(seconds: 5));
      expect(web.evaluations, paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(web.evaluations, greaterThan(paused));
      expect(find.text('學校系統回應逾時。可以再試一次，或直接開啟學校網頁。'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final dark in [false, true]) {
    testWidgets(
      'native loading and error fit large text in ${dark ? 'dark' : 'light'} mode',
      (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? NiuTheme.dark : NiuTheme.light,
            builder: (_, child) => MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: child!,
            ),
            home: AcademicPortalScreen(
              title: '畢業門檻',
              bridge: false,
              target: target,
              extractScript: 'null',
              loadTimeout: const Duration(seconds: 2),
              webViewBuilder: (_) => const SizedBox.expand(),
            ),
          ),
        );
        await tester.pump();
        expect(find.byType(NiuLoading), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pump(const Duration(seconds: 3));
        expect(find.byType(NiuError), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
