import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/core/session/campus_session.dart';
import 'package:niu_mobile/features/authentication/login_screen.dart';
import 'package:niu_mobile/shared/shared.dart';
import 'features/authentication_session_test.dart' show MemoryVault;

void main() {
  for (final dark in [false, true]) {
    testWidgets('native login form validates input at 320/2 dark=$dark', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final session = CampusSession(vault: MemoryVault());
      addTearDown(session.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: dark ? NiuTheme.dark : NiuTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: LoginScreen(session: session),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('帳號密碼與校務系統相同'), findsOneWidget);
      FilledButton button() =>
          tester.widget<FilledButton>(find.widgetWithText(FilledButton, '登入'));
      expect(button().onPressed, isNull);
      final fields = find.byType(TextField);
      // Only letters and digits reach the 學號 field.
      await tester.enterText(fields.at(0), 'b12-3 4');
      expect(tester.widget<TextField>(fields.at(0)).controller!.text, 'b1234');
      await tester.enterText(fields.at(1), 'secret');
      await tester.pump();
      expect(button().onPressed, isNotNull);
      // The password stays hidden until the student asks to see it.
      expect(tester.widget<TextField>(fields.at(1)).obscureText, isTrue);
      await tester.tap(find.byTooltip('顯示密碼'));
      await tester.pump();
      expect(tester.widget<TextField>(fields.at(1)).obscureText, isFalse);
      expect(tester.takeException(), isNull);
    });
  }
}
