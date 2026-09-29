import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/core/session/campus_session.dart';
import 'package:niu_mobile/features/leave/leave_repository.dart';
import 'package:niu_mobile/features/leave/leave_screen.dart';
import 'package:niu_mobile/shared/shared.dart';
import 'features/authentication_session_test.dart' show MemoryVault;

void main() {
  final snapshots = <String, dynamic>{
    'statistics': {
      'updatedAt': '2026-09-29T00:00:00Z',
      'data': {
        'periods': {'事假': '12', '公假': '1'},
        'scope': '本學期',
      },
    },
  };
  test('private leave cache enforces owner and logout epoch', () async {
    final vault = MemoryVault();
    final session = CampusSession(vault: vault, platformCleanup: [])
      ..account = 'b123';
    final repository = LeaveRepository(session);
    await repository.save(snapshots, 0, 'b123');
    expect(await repository.restore(), snapshots);
    session.account = 'b456';
    expect(await repository.restore(), isEmpty);
    await expectLater(repository.save(snapshots, 0, 'b123'), throwsStateError);
    await session.logout();
    expect(vault.values['leaveCache'], isNull);
    await repository.dispose();
    session.dispose();
  });
  test('malformed leave cache rejected', () {
    expect(
      () => LeaveRepository.validate({
        'statistics': {'data': {}},
      }),
      throwsFormatException,
    );
  });
  for (final dark in [false, true]) {
    testWidgets('cached leave dashboard fits small screen dark=$dark', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final vault = MemoryVault()
        ..values['leaveCache'] = jsonEncode({
          'version': 1,
          'account': 'b123',
          'snapshots': snapshots,
        });
      final session = CampusSession(vault: vault)..account = 'b123';
      await tester.pumpWidget(
        MaterialApp(
          theme: dark ? NiuTheme.dark : NiuTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: LeaveScreen(session: session),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('13 節'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    });
  }
}
