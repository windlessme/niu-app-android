import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:niu_mobile/app/campus_shell.dart';
import 'package:niu_mobile/features/home/home_screen.dart';

void main() {
  testWidgets('three tabs navigate while home services are pushed', (
    tester,
  ) async {
    // Phone layout: bottom tabs and the one-day timetable.
    tester.view.physicalSize = const Size(400, 800);
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
                builder: (_, _) => const CampusHomeScreen(name: '測試同學'),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/schedule',
                builder: (_, _) => const Scaffold(body: Text('課表內容')),
              ),
            ],
          ),
        ]),
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
    // The tab pager is a scrollable too; scroll the home page itself.
    await tester.scrollUntilVisible(
      find.text('行事曆'),
      200,
      scrollable: find
          .descendant(
            of: find.byType(CampusHomeScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.ensureVisible(find.text('行事曆'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('行事曆'));
    await tester.pumpAndSettle();
    expect(find.text('校曆詳細畫面'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('tabs swipe, keep their state, and back returns home', (
    tester,
  ) async {
    Widget page(String label) => Scaffold(body: _Counter(label));
    final router = GoRouter(
      routes: [
        CampusShell.route([
          for (final (path, label) in [
            ('/', '首頁內容'),
            ('/schedule', '課表內容'),
            ('/moodle', 'M 園區內容'),
          ])
            StatefulShellBranch(
              routes: [GoRoute(path: path, builder: (_, _) => page(label))],
            ),
        ]),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text('課表內容 0'), findsOneWidget);
    expect(router.state.uri.path, '/schedule');

    await tester.tap(find.text('課表內容 0'));
    await tester.pump();
    await tester.tap(find.text('M 園區'));
    await tester.pumpAndSettle();
    expect(find.text('M 園區內容 0'), findsOneWidget);
    await tester.fling(find.byType(PageView), const Offset(400, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text('課表內容 1'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/');
    expect(find.text('首頁內容 0'), findsOneWidget);
  });

  testWidgets('a swipe that springs back keeps back inside the app', (
    tester,
  ) async {
    bool? handlesBack;
    final router = GoRouter(
      initialLocation: '/schedule',
      routes: [
        CampusShell.route([
          for (final path in ['/', '/schedule', '/moodle'])
            StatefulShellBranch(
              preload: true,
              routes: [
                GoRoute(
                  path: path,
                  builder: (_, _) => Scaffold(body: Text('page $path')),
                ),
              ],
            ),
        ]),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
        // What the app would tell Android about handling back.
        onNavigationNotification: (notification) {
          handlesBack = notification.canHandlePop;
          return true;
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(handlesBack, isTrue);
    // Drag home partly into view, then let go so the page springs back.
    await tester.drag(find.byType(PageView), const Offset(250, 0));
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/schedule');
    expect(handlesBack, isTrue);
  });
}

class _Counter extends StatefulWidget {
  const _Counter(this.label);
  final String label;
  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int taps = 0;
  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: () => setState(() => taps++),
    child: Text('${widget.label} $taps'),
  );
}
