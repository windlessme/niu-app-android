import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:niu_mobile/app/campus_shell.dart';
import 'package:niu_mobile/shared/shared.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets('navigation safe insets and large text dark=$dark', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final router = GoRouter(
        routes: [
          ShellRoute(
            builder: (context, state, child) =>
                CampusShell(path: state.uri.path, child: child),
            routes: [
              GoRoute(
                path: '/',
                builder: (_, _) => const Scaffold(body: Text('首頁內容')),
              ),
              GoRoute(
                path: '/campus',
                builder: (_, _) => const CampusServicesScreen(),
              ),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        MaterialApp.router(
          theme: dark ? NiuTheme.dark : NiuTheme.light,
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
              padding: const EdgeInsets.only(bottom: 24),
            ),
            child: child!,
          ),
        ),
      );
      await tester.tap(find.text('校園'));
      await tester.pumpAndSettle();
      expect(find.text('校園服務'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byTooltip('返回')).height,
        greaterThanOrEqualTo(48),
      );
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      expect(find.text('首頁內容'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
