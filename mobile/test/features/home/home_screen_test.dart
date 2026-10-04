import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:niu_mobile/features/home/home_screen.dart';

void main() {
  testWidgets('home service card routes without manufacturing logged-in data', (
    tester,
  ) async {
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const CampusHomeScreen()),
        GoRoute(
          path: '/attendance',
          builder: (_, _) => const Scaffold(body: Text('掃描入口')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    expect(find.text('登入校務系統'), findsOneWidget);
    await tester.ensureVisible(find.text('M 園區快速點名'));
    await tester.tap(find.text('M 園區快速點名'));
    await tester.pumpAndSettle();
    expect(find.text('掃描入口'), findsOneWidget);
  });

  testWidgets('home shows actual supplied next class in large text', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
          child: const CampusHomeScreen(
            name: '測試同學',
            courses: [
              HomeCourse(
                name: '資料結構',
                time: '08:10–09:00',
                room: 'A101',
                current: true,
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text('資料結構'), findsOneWidget);
    expect(find.text('上課中'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
