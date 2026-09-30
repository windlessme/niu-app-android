import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:niu_mobile/app/campus_shell.dart';
import 'package:niu_mobile/features/home/home_screen.dart';

void main() {
  testWidgets('three tabs navigate while home services are pushed', (
    tester,
  ) async {
    final router = GoRouter(
      routes: [
        ShellRoute(
          builder: (context, state, child) =>
              CampusShell(path: state.uri.path, child: child),
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => const CampusHomeScreen(name: '測試同學'),
            ),
            GoRoute(
              path: '/schedule',
              builder: (_, _) => const Scaffold(body: Text('課表內容')),
            ),
          ],
        ),
        GoRoute(
          path: '/calendar',
          builder: (_, _) => const Scaffold(body: Text('校曆詳細畫面')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        routerConfig: router,
      ),
    );
    expect(find.byType(NavigationDestination), findsNWidgets(3));
    expect(find.text('校園'), findsNothing);
    await tester.tap(find.text('課表'));
    await tester.pumpAndSettle();
    expect(find.text('課表內容'), findsOneWidget);
    await tester.tap(find.text('首頁'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('行事曆'), 200);
    await tester.ensureVisible(find.text('行事曆'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('行事曆'));
    await tester.pumpAndSettle();
    expect(find.text('校曆詳細畫面'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });
}
