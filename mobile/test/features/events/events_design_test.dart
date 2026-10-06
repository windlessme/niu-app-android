import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/features/events/event_actions.dart';
import 'package:niu_mobile/features/events/events_screen.dart';
import 'package:niu_mobile/features/events/event_widgets.dart';
import 'package:niu_mobile/shared/shared.dart';
import 'package:niu_mobile/features/events/event_models.dart';

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

class FakeEventActions implements EventActions {
  FakeEventActions([this.mine = const []]);
  final List<CampusEvent> mine;
  final calls = <String>[];

  @override
  Future<List<CampusEvent>> registrations() async => mine;

  List<CampusEvent> open = const [];
  @override
  Future<List<CampusEvent>> available() async => open;

  Map<String, Object?> saved = {};
  @override
  Future<EventActionResult> register(CampusEvent event) async {
    calls.add('register');
    return const EventActionResult(true, '報名成功');
  }

  @override
  Future<EventRegistrationForm> loadForm(CampusEvent event) async {
    calls.add('load');
    return EventRegistrationForm.fromJson({
      'tel': '0900',
      'email': 'a@b.c',
      'memo': '',
      'food': [
        {'value': '3', 'label': '不用餐', 'checked': true},
        {'value': '2', 'label': '素食', 'checked': false},
      ],
      'proof': [],
      'info': [
        ['學號', 'B000'],
      ],
    });
  }

  @override
  Future<EventActionResult> save(
    CampusEvent event, {
    required String tel,
    required String email,
    required String memo,
    String? food,
    String? proof,
  }) async {
    calls.add('save');
    saved = {'tel': tel, 'email': email, 'food': food};
    return const EventActionResult(true, '已儲存修改');
  }

  @override
  Future<EventActionResult> cancel(CampusEvent event) async {
    calls.add('cancel');
    return const EventActionResult(true, '已取消報名');
  }
}

void main() {
  final event = CampusEvent.fromJson({
    'id': '11205',
    'name': '永續校園工作坊',
    'department': '學務處',
    'location': '圖書館',
    'time': '2026/10/01 14:00',
    'hours': '專業進取（已認證，2 小時）',
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
              actions: FakeEventActions(),
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
        expect(find.byType(NiuScrollPage), findsOneWidget);
        expect(find.text('-'), findsOneWidget);
        expect(find.text('編號 11205'), findsOneWidget);
        // 多元認證 is one plain metadata line, not a tag.
        expect(find.text('專業進取　2 小時'), findsOneWidget);
        expect(find.textContaining('已認證'), findsNothing);
        await tester.tap(find.text('專業進取'));
        await tester.pumpAndSettle();
        expect(find.byType(EventListCard), findsOneWidget);
        await tester.tap(find.text('全部認證'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        for (final query in ['學務處', '圖書館', '永續', '11205', '#112', 'No.11205']) {
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
        expect(find.byType(NiuCard), findsWidgets);
        final action = find.widgetWithText(FilledButton, '報名');
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
        // Native confirmation, then the (fake) school submission.
        await tester.tap(find.widgetWithText(FilledButton, '報名').last);
        await tester.pumpAndSettle();
        expect(find.text('報名成功'), findsOneWidget);
        expect(find.widgetWithText(FilledButton, '已報名'), findsOneWidget);
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
      find.text('報名人數'),
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
      final actions = FakeEventActions();
      await tester.pumpWidget(
        MaterialApp(
          theme: NiuTheme.light,
          home: EventsScreen(
            actions: actions,
            loaderBuilder: (_, _) =>
                SnapshotRoute(events: ++calls == 1 ? null : [event]),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('尚未同步活動'), findsOneWidget);
      expect(find.byType(EventListCard), findsNothing);
      await tester.tap(find.widgetWithText(FilledButton, '同步活動'));
      await tester.pumpAndSettle();
      expect(calls, 2);
      await tester.tap(find.text(event.name));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '報名'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(actions.calls, isEmpty);
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.byType(EventListCard), findsOneWidget);
    },
  );

  testWidgets('registered event edits and cancels natively', (tester) async {
    final actions = FakeEventActions();
    await tester.pumpWidget(
      MaterialApp(
        theme: NiuTheme.light,
        home: EventDetailScreen(event: event, applied: true, actions: actions),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '修改資料'));
    await tester.pumpAndSettle();
    expect(find.text('B000'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, '電話'), '0911');
    await tester.ensureVisible(find.text('素食'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('素食'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '儲存修改'));
    await tester.pumpAndSettle();
    expect(actions.saved, {'tel': '0911', 'email': 'a@b.c', 'food': '2'});
    expect(find.text('已儲存修改'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, '取消報名'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '取消報名'));
    await tester.pumpAndSettle();
    expect(actions.calls, ['load', 'save', 'cancel']);
    expect(find.text('已取消報名'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '修改資料'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('already registered events are hidden from available ones', (
    tester,
  ) async {
    final other = CampusEvent.fromJson({'id': '2', 'name': '職涯講座'});
    await tester.pumpWidget(
      MaterialApp(
        theme: NiuTheme.light,
        home: EventsScreen(
          actions: FakeEventActions([event]),
          loaderBuilder: (_, applied) =>
              SnapshotRoute(events: applied ? [event] : [event, other]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('職涯講座'), findsOneWidget);
    expect(find.text(event.name), findsNothing);
    await tester.tap(find.text('我的報名'));
    await tester.pumpAndSettle();
    expect(find.text(event.name), findsOneWidget);
  });
}
