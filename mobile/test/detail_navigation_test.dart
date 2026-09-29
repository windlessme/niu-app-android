import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:niu_mobile/app/campus_shell.dart';
import 'package:niu_mobile/features/moodle/moodle_screen.dart';
import 'package:niu_mobile/shared/shared.dart';

void main() {
  testWidgets('Moodle details hide root tabs and back restores the root page', (
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
              builder: (context, _) => Scaffold(
                body: TextButton(
                  onPressed: () => pushMoodle(
                    context,
                    const Scaffold(
                      appBar: IosPageHeader(title: '課程詳情'),
                      body: Text('課程內容'),
                    ),
                  ),
                  child: const Text('開啟課程'),
                ),
              ),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(theme: NiuTheme.light, routerConfig: router),
    );
    expect(find.text('校園'), findsOneWidget);
    await tester.tap(find.text('開啟課程'));
    await tester.pumpAndSettle();
    expect(find.text('課程內容'), findsOneWidget);
    expect(find.text('校園'), findsNothing);
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.text('開啟課程'), findsOneWidget);
    expect(find.text('校園'), findsOneWidget);
  });
}
