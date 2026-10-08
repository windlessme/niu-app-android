import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/app/auth_gate.dart';
import 'package:niu_mobile/core/session/campus_session.dart';
import 'package:niu_mobile/features/authentication/login_screen.dart';
import 'package:niu_mobile/shared/shared.dart';
import '../support/fakes.dart';

void main() {
  Future<CampusSession> pumpGate(WidgetTester tester) async {
    final session = CampusSession(vault: MemoryVault(), platformCleanup: []);
    addTearDown(session.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: NiuTheme.light,
        home: AuthGate(
          title: '課表',
          session: session,
          child: const Text('課表內容'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
    return session;
  }

  testWidgets('a tab built while signed out opens after signing in elsewhere', (
    tester,
  ) async {
    // Preloaded 課表 and M 園區 tabs show their login while the student
    // signs in on the home tab instead.
    final session = await pumpGate(tester);
    await session.enterDemo();
    await tester.pumpAndSettle();
    expect(find.text('課表內容'), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);
  });

  testWidgets('the gate\'s own sign-in finishes before the content shows', (
    tester,
  ) async {
    await pumpGate(tester);
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'niulifedemo');
    await tester.enterText(fields.at(1), 'x9Ru-ZeuT-pXnq');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '登入'));
    await tester.pumpAndSettle();
    expect(find.text('課表內容'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
