import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/features/moodle/moodle_screen.dart';

void main() {
  testWidgets('refresh retains results, handles sync errors and recovers', (
    tester,
  ) async {
    var calls = 0;
    final pending = Completer<List<Map<String, dynamic>>>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MoodleList(
            load: () {
              calls++;
              if (calls == 1) {
                return Future.value([
                  {'name': '已儲存課程'},
                ]);
              }
              if (calls == 2) return pending.future;
              if (calls == 3) throw StateError('offline');
              return Future.value([
                {'name': '最新課程'},
              ]);
            },
            item: (item) => Text(item['name'] as String),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final refresh = tester.widget<RefreshIndicator>(
      find.byType(RefreshIndicator),
    );
    final first = refresh.onRefresh();
    await tester.pump();
    expect(find.text('已儲存課程'), findsOneWidget);
    expect(find.text('正在更新，顯示上次資料…'), findsOneWidget);
    await refresh.onRefresh();
    expect(calls, 2);
    pending.completeError(StateError('offline'));
    await first;
    await tester.pumpAndSettle();
    expect(find.text('更新失敗，顯示上次資料。點此重試'), findsOneWidget);
    await tester.tap(find.text('更新失敗，顯示上次資料。點此重試'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('已儲存課程'), findsOneWidget);
    await tester.tap(find.text('更新失敗，顯示上次資料。點此重試'));
    await tester.pumpAndSettle();
    expect(find.text('最新課程'), findsOneWidget);
    expect(find.text('已儲存課程'), findsNothing);
  });
}
