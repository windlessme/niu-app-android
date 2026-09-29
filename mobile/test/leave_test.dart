import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/core/session/campus_session.dart';
import 'package:niu_mobile/features/leave/leave_repository.dart';
import 'package:niu_mobile/features/leave/leave_screen.dart';
import 'package:niu_mobile/features/leave/leave_widgets.dart';
import 'package:niu_mobile/shared/shared.dart';
import 'features/authentication_session_test.dart' show MemoryVault;

void main() {
  test('statistics agrees once; application still requires interaction', () {
    final result = Process.runSync('node', [
      '-e',
      '''
const assert=require('node:assert/strict');let clicks=0;
const button={value:'同意',disabled:false,click:()=>clicks++};
const doc={location:{href:'https://acade.niu.edu.tw/NIU/Application/SEC/SEC20/SEC2010_02.aspx'},getElementById:()=>button};
global.window={document:doc,frames:[]};
assert.equal(eval(${jsonEncode(leaveMenuNavigation(true))}), 'interaction-required');
assert.equal(clicks,0);
const script=${jsonEncode(leaveMenuNavigation(true, agreeForStatistics: true))};
assert.equal(eval(script),null);eval(script);assert.equal(clicks,1);
''',
    ]);
    expect(result.exitCode, 0, reason: result.stderr.toString());
  });
  for (final dark in [false, true]) {
    testWidgets('long leave categories wrap with semantic counts dark=$dark', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          theme: dark ? NiuTheme.dark : NiuTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: const Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: EdgeInsets.all(NiuSpacing.xl),
                child: LeaveTypeStatistics(
                  periods: {'公假': '1', '產假（產前假／陪產假／流產假／哺乳假）': '0', '病假': '0'},
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.bySemanticsLabel('公假 1 節'), findsOneWidget);
      expect(find.text('0'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
      semantics.dispose();
      await tester.pumpWidget(const SizedBox());
    });
  }
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
    for (final inset in [24.0, 48.0]) {
      testWidgets('pagination clears system inset $inset dark=$dark', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final vault = MemoryVault()
          ..values['leaveCache'] = jsonEncode({
            'version': 1,
            'account': 'b123',
            'snapshots': {
              ...snapshots,
              'list': {
                'updatedAt': '2026-09-29T00:00:00Z',
                'data': {
                  'records': [],
                  'page': '1',
                  'pages': '1',
                  'total': '0',
                },
              },
            },
          });
        final session = CampusSession(vault: vault)..account = 'b123';
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? NiuTheme.dark : NiuTheme.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(2),
                padding: EdgeInsets.only(bottom: inset),
                viewPadding: EdgeInsets.only(bottom: inset),
                systemGestureInsets: EdgeInsets.only(bottom: inset),
              ),
              child: child!,
            ),
            home: LeaveScreen(session: session),
          ),
        );
        await tester.pumpAndSettle();
        final scroll = find.byType(Scrollable).first;
        await tester.scrollUntilVisible(
          find.text('下一頁'),
          100,
          scrollable: scroll,
        );
        expect(
          tester
              .widget<TextButton>(find.widgetWithText(TextButton, '上一頁'))
              .onPressed,
          isNull,
        );
        expect(
          tester
              .widget<TextButton>(find.widgetWithText(TextButton, '下一頁'))
              .onPressed,
          isNull,
        );
        final position = tester.state<ScrollableState>(scroll).position;
        position.jumpTo(position.maxScrollExtent);
        await tester.pump();
        final last = find.widgetWithText(TextButton, '更新紀錄');
        expect(
          tester.getBottomRight(last).dy,
          lessThanOrEqualTo(568 - inset - NiuSpacing.xxl),
        );
        expect(tester.getSize(last).height, greaterThanOrEqualTo(48));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        session.dispose();
      });
    }
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
