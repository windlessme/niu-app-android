import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/features/attendance/attendance_entry.dart';
import 'package:niu_mobile/features/moodle/moodle_repository.dart';
import 'package:niu_mobile/shared/shared.dart';

void main() {
  testWidgets('a cold start waits for M 園區 instead of showing its page', (
    tester,
  ) async {
    final restored = Completer<MoodleRepository?>();
    await tester.pumpWidget(
      MaterialApp(
        theme: NiuTheme.light,
        home: AttendanceEntry(
          restore: () => restored.future,
          signIn: (_) => const Text('M 園區登入'),
        ),
      ),
    );
    expect(find.text('正在連接 M 園區'), findsOneWidget);
    expect(find.text('M 園區登入'), findsNothing);

    // No saved sign-in: only then the M 園區 login.
    restored.complete(null);
    await tester.pumpAndSettle();
    expect(find.text('M 園區登入'), findsOneWidget);
  });

  testWidgets('a failed restore falls back to signing in', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: NiuTheme.light,
        home: AttendanceEntry(
          restore: () async => throw StateError('offline'),
          signIn: (_) => const Text('M 園區登入'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('M 園區登入'), findsOneWidget);
  });
}
