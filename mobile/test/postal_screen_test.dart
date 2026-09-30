import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/core/session/campus_session.dart';
import 'package:niu_mobile/features/postal/postal_models.dart';
import 'package:niu_mobile/features/postal/postal_screen.dart';
import 'package:niu_mobile/features/postal/postal_service.dart';
import 'package:niu_mobile/shared/shared.dart';
import 'features/authentication_session_test.dart' show MemoryVault;

class FakePostal extends PostalService {
  FakePostal(this.queries);
  final List<PostalQuery> queries;
  @override
  Future<PostalPage> search(PostalQuery query) async {
    queries.add(query.normalized);
    return PostalPage(
      records: query.status == PostalStatus.waiting
          ? const [
              PostalRecord(
                sequence: '1',
                receivedDate: '115/10/01',
                trackingNumber: 'RR123',
                unit: '資工系',
                recipient: '王小明',
                category: '包裹',
                quantity: '1',
                signature: '否',
                completedDate: '',
                note: '',
                status: PostalStatus.waiting,
              ),
            ]
          : const [],
      query: query.normalized,
      pageIndex: 0,
      pageCount: 1,
    );
  }

  @override
  void close() {}
}

void main() {
  testWidgets(
    'own name is filled on request, searched once and filtered locally',
    (tester) async {
      final queries = <PostalQuery>[];
      final session = CampusSession(vault: MemoryVault(), platformCleanup: [])
        ..account = 'b123'
        ..profile = {'chName': '王小明'};
      addTearDown(session.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: NiuTheme.light,
          home: PostalScreen(
            session: session,
            service: () => FakePostal(queries),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Nothing is filled or searched until the student asks.
      expect(queries, isEmpty);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        '',
      );
      await tester.tap(find.text('帶入我的姓名'));
      await tester.pump();
      expect(find.text('帶入我的姓名'), findsNothing);
      expect(queries, isEmpty);
      await tester.tap(find.widgetWithText(FilledButton, '查詢'));
      await tester.pumpAndSettle();
      // 全部 queries every status (the school form accepts one at a time).
      expect(queries.map((q) => q.status).toSet(), PostalStatus.values.toSet());
      expect(queries.every((q) => q.name == '王小明'), isTrue);
      expect(find.text('RR123'), findsOneWidget);
      expect(find.text('1 筆'), findsOneWidget);
      // Status chips filter the results locally without querying again.
      queries.clear();
      await tester.tap(find.text('已領取 0'));
      await tester.pumpAndSettle();
      expect(queries, isEmpty);
      expect(find.text('沒有已領取的紀錄'), findsOneWidget);
      await tester.tap(find.text('未領取 1'));
      await tester.pumpAndSettle();
      expect(find.text('RR123'), findsOneWidget);
      // Edited criteria are flagged until searched again.
      await tester.enterText(find.byType(TextField).first, '王大明');
      await tester.pump();
      expect(find.text('條件已變更，重新查詢以更新結果'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  for (final dark in [false, true]) {
    testWidgets('narrow large text fits dark=$dark', (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final session = CampusSession(vault: MemoryVault(), platformCleanup: [])
        ..account = 'b123'
        ..profile = {'chName': '王小明'};
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
          home: PostalScreen(session: session, service: () => FakePostal([])),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('帶入我的姓名'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, '查詢'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('更多條件 stays open while typing', (tester) async {
    final queries = <PostalQuery>[];
    final session = CampusSession(vault: MemoryVault(), platformCleanup: [])
      ..account = 'b123';
    addTearDown(session.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: NiuTheme.light,
        home: PostalScreen(
          session: session,
          service: () => FakePostal(queries),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('更多條件'));
    await tester.pumpAndSettle();
    final phone = find.widgetWithText(TextField, '手機號碼');
    await tester.tap(phone);
    await tester.enterText(phone, '0912');
    await tester.pumpAndSettle();
    expect(phone, findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, '郵件號碼'), 'RR1');
    await tester.pumpAndSettle();
    expect(find.text('0912'), findsOneWidget);
    // The floating 手機號碼 label sits below the 更多條件 header.
    expect(
      tester.getTopLeft(find.text('手機號碼')).dy,
      greaterThanOrEqualTo(tester.getBottomLeft(find.byType(ListTile)).dy),
    );
    expect(find.text('RR1'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '查詢'));
    await tester.pumpAndSettle();
    expect(queries.first.phone, '0912');
  });
}
