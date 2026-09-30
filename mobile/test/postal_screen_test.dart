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
  testWidgets('opens with the student\'s own name already searched', (
    tester,
  ) async {
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
    expect(queries.single.name, '王小明');
    expect(queries.single.status, PostalStatus.waiting);
    expect(find.text('RR123'), findsOneWidget);
    await tester.tap(find.text('已領取'));
    await tester.pumpAndSettle();
    expect(queries.last.status, PostalStatus.collected);
    expect(find.text('沒有已領取的紀錄'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
