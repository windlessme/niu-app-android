import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:niu_mobile/app/campus_shell.dart';

void main() {
  testWidgets('bottom tabs navigate while service details can be pushed', (
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
              builder: (_, _) => const Scaffold(body: Text('首頁內容')),
            ),
            GoRoute(
              path: '/campus',
              builder: (_, _) => const CampusServicesScreen(),
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
    await tester.tap(find.text('校園'));
    await tester.pumpAndSettle();
    expect(find.text('校園服務'), findsOneWidget);
    await tester.tap(find.text('學年度行事曆'));
    await tester.pumpAndSettle();
    expect(find.text('校曆詳細畫面'), findsOneWidget);
    expect(find.text('首頁'), findsNothing);
  });
}
