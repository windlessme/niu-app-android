import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/features/events/events_screen.dart';
import 'package:niu_mobile/features/events/event_widgets.dart';
import 'package:niu_mobile/shared/shared.dart';

class SnapshotRoute extends StatefulWidget {
  const SnapshotRoute({super.key, this.events});
  final List<CampusEvent>? events;
  @override
  State<SnapshotRoute> createState() => _SnapshotRouteState();
}

class _SnapshotRouteState extends State<SnapshotRoute> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => Navigator.pop(context, widget.events),
    );
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: Text('同步中'));
}

void main() {
  final event = CampusEvent.fromJson({
    'id': '1',
    'name': '永續校園工作坊',
    'department': '學務處',
    'location': '圖書館',
    'time': '2026/10/01 14:00',
    'hours': '2 小時',
  });
  for (final dark in [false, true]) {
    testWidgets(
      'events preserve tab queries, snapshots and detail navigation at 320/2 dark=$dark',
      (tester) async {
        tester.view.physicalSize = const Size(320, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final calls = <bool>[];
        var fail = false;
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? NiuTheme.dark : NiuTheme.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: EventsScreen(
              loaderBuilder: (_, applied) {
                calls.add(applied);
                return SnapshotRoute(
                  events: fail
                      ? null
                      : applied
                      ? []
                      : [event],
                );
              },
              actionBuilder: (context, event, applied) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('完成變更'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(calls, [false]);
        expect(find.byType(IosPageHeader), findsOneWidget);
        expect(find.text('-'), findsOneWidget);
        expect(tester.takeException(), isNull);
        for (final query in ['學務處', '圖書館', '永續']) {
          await tester.enterText(find.byType(TextField), query);
          await tester.pumpAndSettle();
          expect(find.byType(EventListCard), findsOneWidget);
        }
        await tester.enterText(find.byType(TextField), '不存在');
        await tester.pumpAndSettle();
        expect(find.text('找不到符合的活動'), findsOneWidget);
        await tester.tap(find.text('我的報名'));
        await tester.pumpAndSettle();
        expect(calls, [false, true]);
        expect(find.text('目前沒有報名紀錄'), findsOneWidget);
        await tester.tap(find.text('可報名活動'));
        await tester.pumpAndSettle();
        expect(find.text('找不到符合的活動'), findsOneWidget);
        expect(calls.length, 2);
        await tester.enterText(find.byType(TextField), '永續');
        await tester.pumpAndSettle();
        await tester.tap(find.text(event.name));
        await tester.pumpAndSettle();
        expect(find.byType(HeroCard), findsOneWidget);
        final action = find.widgetWithText(FilledButton, '前往校方報名');
        expect(tester.getSize(action).height, greaterThanOrEqualTo(48));
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('返回'));
        await tester.pumpAndSettle();
        expect(calls.length, 2);
        expect(find.text('永續'), findsOneWidget);
        await tester.tap(find.text(event.name));
        await tester.pumpAndSettle();
        await tester.tap(action);
        await tester.pumpAndSettle();
        await tester.tap(find.text('完成變更'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('返回'));
        await tester.pumpAndSettle();
        expect(calls, [false, true, false]);
        fail = true;
        await tester.tap(find.byTooltip('同步活動'));
        await tester.pumpAndSettle();
        expect(find.text('同步未完成，仍顯示上次的活動資料。'), findsOneWidget);
        expect(find.byType(EventListCard), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('missing detail values remain unknown instead of zero capacity', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: NiuTheme.light,
        home: EventDetailScreen(event: CampusEvent.fromJson({})),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('人數'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('-'), findsWidgets);
    expect(find.textContaining('0 人'), findsNothing);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
  });

  testWidgets(
    'initial cancelled sync can retry and unchanged action does not reload',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: NiuTheme.light,
          home: EventsScreen(
            loaderBuilder: (_, _) =>
                SnapshotRoute(events: ++calls == 1 ? null : [event]),
            actionBuilder: (context, _, _) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('取消操作'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('尚未同步活動'), findsOneWidget);
      expect(find.byType(EventListCard), findsNothing);
      await tester.tap(find.widgetWithText(TextButton, '同步活動'));
      await tester.pumpAndSettle();
      expect(calls, 2);
      await tester.tap(find.text(event.name));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '前往校方報名'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消操作'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.byType(EventListCard), findsOneWidget);
    },
  );
}
