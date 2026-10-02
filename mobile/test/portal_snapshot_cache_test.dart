import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/core/session/portal_snapshot_cache.dart';
import 'package:niu_mobile/core/web/academic_portal_screen.dart';
import 'package:niu_mobile/shared/shared.dart';

import 'features/authentication_session_test.dart' show MemoryVault;
import 'schedule_screen_test.dart' show ScheduleSession;

void main() {
  late MemoryVault vault;
  late ScheduleSession session;
  setUp(() {
    vault = MemoryVault();
    session = ScheduleSession(vault)..account = 'b123';
  });
  tearDown(() => session.dispose());

  Future<void> seed(
    Map<String, dynamic> data, {
    String key = 'grades.history',
  }) => PortalSnapshotCache.of(session).write(
    key,
    data,
    epoch: session.coordinator.epoch,
    owner: 'b123',
    now: DateTime.utc(2026, 10, 1, 8),
  );

  test('snapshots stay with their account and leave at logout', () async {
    final cache = PortalSnapshotCache.of(session);
    await seed({
      'rows': [
        ['1141', '必修', '3', '微積分', '88'],
      ],
    });
    await seed({'student': 'b123'}, key: 'registration');
    final read = await cache.read('grades.history');
    expect(read!.updatedAt, DateTime.utc(2026, 10, 1, 8));
    expect((read.data['rows'] as List).single, contains('微積分'));
    expect((await cache.read('registration'))!.data['student'], 'b123');
    expect(await cache.read('grades.midterm'), isNull);

    session.account = 'b456';
    expect(await cache.read('grades.history'), isNull);
    await expectLater(
      cache.write('grades.history', {}, epoch: 0, owner: 'b123'),
      throwsStateError,
    );

    session.account = 'b123';
    await session.logout();
    expect(vault.values['portalCache'], isNull);
  });

  Widget portal() => MaterialApp(
    theme: NiuTheme.light,
    home: AcademicPortalScreen(
      title: '成績',
      session: session,
      cacheKey: 'grades.history',
      extractScript: 'null',
      loadTimeout: const Duration(seconds: 1),
      webViewBuilder: (_) => const SizedBox.expand(),
      snapshotBuilder: (_, value) =>
          Text('共 ${((value as Map)['rows'] as List).length} 門'),
    ),
  );

  testWidgets('the last grades show at once and outlast a failed update', (
    tester,
  ) async {
    await seed({
      'rows': [
        ['1141', '必修', '3', '微積分', '88'],
        ['1141', '必修', '2', '英文', '90'],
      ],
    });
    await tester.pumpWidget(portal());
    await tester.pump();
    await tester.pump();
    expect(find.text('共 2 門'), findsOneWidget);
    expect(find.text('正在更新'), findsOneWidget);
    expect(find.text('正在向學校系統讀取資料'), findsNothing);

    // The school never answers: keep the cached grades, say so, offer retry.
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('共 2 門'), findsOneWidget);
    expect(find.text('更新失敗，顯示上次的資料'), findsOneWidget);
    expect(find.text('無法取得資料'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('without a cache the page still waits for the school', (
    tester,
  ) async {
    await tester.pumpWidget(portal());
    await tester.pump();
    expect(find.text('正在向學校系統讀取資料'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('無法取得資料'), findsOneWidget);
  });

  testWidgets('a demo page counts as just updated', (tester) async {
    session.account = null;
    await session.enterDemo();
    await tester.pumpWidget(
      MaterialApp(
        theme: NiuTheme.light,
        home: AcademicPortalScreen(
          title: '成績',
          session: session,
          cacheKey: 'grades.history',
          extractScript: 'null',
          demoSnapshot: () => {'rows': []},
          snapshotBuilder: (_, value) => const Text('示範成績'),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('示範成績'), findsOneWidget);
    expect(find.text('尚未更新'), findsNothing);
  });
}
