import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:niu_mobile/app/campus_shell.dart';
import 'package:niu_mobile/shared/shared.dart';

void main() {
  testWidgets(
    'campus registration entry navigates to the certificate feature',
    (tester) async {
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (_, _) => const CampusServicesScreen()),
          GoRoute(
            path: '/registration',
            builder: (_, _) => const Scaffold(body: Text('註冊與證明測試頁')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        MaterialApp.router(theme: NiuTheme.light, routerConfig: router),
      );
      await tester.scrollUntilVisible(find.text('在學證明'), 200);
      await tester.ensureVisible(find.text('在學證明'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('在學證明'));
      await tester.pumpAndSettle();
      expect(find.text('註冊與證明測試頁'), findsOneWidget);
    },
  );
}
