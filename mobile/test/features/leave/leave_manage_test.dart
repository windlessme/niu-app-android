import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/core/session/campus_session.dart';
import 'package:niu_mobile/features/leave/leave_application_screen.dart';
import 'package:niu_mobile/features/leave/leave_application_scripts.dart';
import 'package:niu_mobile/features/leave/leave_manage.dart';
import 'package:niu_mobile/features/leave/leave_screen.dart';
import 'package:niu_mobile/features/leave/leave_withdraw_screen.dart';
import 'package:niu_mobile/shared/shared.dart';

import '../../support/fakes.dart';

void main() {
  test('學生請假修改 scripts and the modify/supplement guards', () {
    final dir = Directory.systemTemp.createTempSync('leave_manage');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/scripts.json')
      ..writeAsStringSync(
        jsonEncode({
          'navigation': leaveManageNavigation,
          'extract': leaveManageExtract,
          'openMissing': leaveManageOpen('D9', 'MOD'),
          'openD2Detail': leaveManageOpen('D2', 'DETAIL'),
          'withdrawD1': leaveWithdraw('D1'),
          'withdrawD2': leaveWithdraw('D2'),
          'state': leaveWithdrawState,
          'reset': leaveManageReset,
          'listedD1': leaveManageListed('D1'),
          'runtime': leaveApplicationRuntime,
        }),
      );
    final result = Process.runSync('node', [
      'test/fixtures/leave_manage_dom.cjs',
      file.path,
    ]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  });

  test('actions come only from the school list', () {
    final actions = LeaveActions.fromSnapshot({
      'actions': [
        {'formNo': 'D1', 'withdraw': true},
        {'formNo': '', 'modify': true},
        'not a row',
      ],
    });
    expect(actions.single.formNo, 'D1');
    expect(actions.single.any, isTrue);
    expect(LeaveActions.fromSnapshot(null), isEmpty);
  });

  group('demo', () {
    late CampusSession session;
    setUp(() async {
      session = CampusSession(vault: MemoryVault(), platformCleanup: []);
      await session.enterDemo();
    });
    tearDown(() => session.dispose());

    Future<void> openRecord(WidgetTester tester, String status) async {
      tester.view.physicalSize = const Size(400, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: NiuTheme.light,
          home: LeaveScreen(session: session),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(status).first);
      await tester.pumpAndSettle();
    }

    testWidgets('a returned form offers modify, supplement and withdraw', (
      tester,
    ) async {
      await openRecord(tester, '退回');
      expect(find.text('操作'), findsOneWidget);
      expect(find.text('修改假單'), findsOneWidget);
      expect(find.text('補交證明文件'), findsOneWidget);
      expect(find.text('撤回假單'), findsOneWidget);
    });

    testWidgets('an approved form offers nothing', (tester) async {
      await openRecord(tester, '核准');
      expect(find.text('操作'), findsNothing);
      expect(find.text('撤回假單'), findsNothing);
    });

    testWidgets('modify opens the filed form with its values', (tester) async {
      await openRecord(tester, '退回');
      await tester.tap(find.text('修改假單'));
      await tester.pumpAndSettle();
      expect(find.text('修改假單'), findsOneWidget); // The form's title.
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.tap(find.text('同意並開始修改'));
      await tester.pumpAndSettle();
      expect(find.text('處理戶籍資料'), findsOneWidget);
      expect(find.text('確認修改'), findsOneWidget);
    });

    testWidgets('supplement locks the fields and needs a file', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: NiuTheme.light,
          home: LeaveApplicationScreen(
            session: session,
            leave: const LeaveEntry.supplement('D1150921'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.tap(find.text('同意並開始補件'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
      expect(find.text('請先附加證明文件'), findsOneWidget);
      final send = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '送出補交'),
      );
      expect(send.onPressed, isNotNull); // It explains what is missing.
      expect(find.text('事後補件'), findsNothing);
    });

    testWidgets('withdraw asks first, then reports the result', (tester) async {
      await openRecord(tester, '審核中');
      await tester.tap(find.text('撤回假單'));
      await tester.pumpAndSettle();
      expect(find.text('撤回這張假單？'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, '保留假單'));
      await tester.pumpAndSettle();
      expect(find.byType(LeaveWithdrawScreen), findsNothing);

      await tester.tap(find.text('撤回假單'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '撤回假單'));
      await tester.pumpAndSettle();
      expect(find.text('已撤回假單'), findsOneWidget);
      await tester.tap(find.text('返回請假紀錄'));
      await tester.pumpAndSettle();
      // Back on the records, read again.
      expect(find.byType(LeaveWithdrawScreen), findsNothing);
      expect(find.text('請假紀錄'), findsWidgets);
    });
  });
}
