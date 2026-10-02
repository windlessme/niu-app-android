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
          CampusShell.route([
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/',
                  builder: (_, _) => const Scaffold(body: Text('首頁內容')),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/schedule',
                  builder: (_, _) => const NiuScrollPage(
                    title: '課表',
                    large: true,
                    showBack: false,
                    children: [Text('課表內容')],
                  ),
                ),
              ],
            ),
          ]),
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
      await tester.tap(find.text('課表').last);
      await tester.pumpAndSettle();
      expect(find.text('課表內容'), findsOneWidget);
      expect(tester.takeException(), isNull);
      // The tab title shares the action row; content starts right below it.
      expect(
        tester.getTopLeft(find.text('課表內容')).dy,
        lessThan(kToolbarHeight + NiuSpacing.xl),
      );
      // Tab roots have no back arrow; the navigation bar switches tabs.
      expect(find.byTooltip('返回'), findsNothing);
      for (final label in ['首頁', 'M 園區']) {
        expect(
          tester
              .getSize(
                find.ancestor(
                  of: find.text(label),
                  matching: find.byType(NavigationDestination),
                ),
              )
              .height,
          greaterThanOrEqualTo(48),
        );
      }
      await tester.tap(find.text('首頁'));
      await tester.pumpAndSettle();
      expect(find.text('首頁內容'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
