import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/core/session/campus_session.dart';
import 'package:niu_mobile/features/events/event_actions.dart';
import 'package:niu_mobile/features/events/event_batch.dart';
import 'package:niu_mobile/features/events/event_favorites.dart';
import 'package:niu_mobile/features/events/event_models.dart';
import 'package:niu_mobile/features/events/events_screen.dart';
import 'package:niu_mobile/shared/shared.dart';

import '../../support/fakes.dart';
import 'events_design_test.dart' show FakeEventActions, SnapshotRoute;

CampusEvent event(
  String id, {
  String status = '報名中',
  String registration = '2026/10/01 ~ 2026/10/20',
  String people = '',
}) => CampusEvent.fromJson({
  'id': id,
  'name': '活動 $id',
  'status': status,
  'registration': registration,
  'people': people,
  'time': '2026/10/25 13:30 ~ 2026/10/25 16:00',
});

/// 12:00 Taipei on 2026-10-10.
final noon = DateTime.utc(2026, 10, 10, 4);

EventEligibility judge(CampusEvent e, {Set<String> applied = const {}}) =>
    EventEligibility.evaluate(
      e,
      appliedIds: applied,
      uncertainIds: const {'9'},
      now: noon,
    );

void main() {
  test('only an explicit open state inside the published dates is sent', () {
    expect(judge(event('1')).canSubmit, isTrue);
    expect(judge(event('1'), applied: {'1'}).reason, contains('已報名'));
    expect(judge(event('9')).reason, contains('結果不明'));
    expect(judge(event('')).reason, contains('編號'));
    expect(judge(event('2', status: '已截止')).canSubmit, isFalse);
    expect(judge(event('3', status: '尚未開放')).canSubmit, isFalse);
    expect(judge(event('4', status: '已額滿')).canSubmit, isFalse);
    expect(judge(event('5', status: '')).reason, contains('狀態空白'));
    expect(
      judge(event('6', registration: '2026/10/11 ~ 2026/10/20')).reason,
      contains('還沒到'),
    );
    // A date-only end is the whole day: still open on 10/10.
    expect(
      judge(event('7', registration: '2026/10/01 ~ 2026/10/10')).canSubmit,
      isTrue,
    );
    expect(
      judge(event('8', registration: '2026/10/01 ~ 2026/10/10 11:59')).reason,
      contains('已超過'),
    );
    // Unknown dates do not block an explicit 報名中.
    expect(judge(event('10', registration: '依公告')).canSubmit, isTrue);
  });

  test('full only when the numbers say what they count', () {
    expect(EventEligibility.explicitlyFull('正取：27 / 27，備取：5 / 5'), isTrue);
    expect(EventEligibility.explicitlyFull('正取：27 / 27，備取：0 / 5'), isFalse);
    expect(EventEligibility.explicitlyFull('名額 30，已報名 30'), isTrue);
    expect(EventEligibility.explicitlyFull('30人\n10人'), isFalse);
    expect(EventEligibility.explicitlyFull('已報名 38 / 60 人'), isFalse);
  });

  test('registration dates accept a missing space and 上午/下午', () {
    final dates = EventEligibility.registrationDates(
      '2026/10/0412:00 ~ 2026/10/10 下午 5:30',
    );
    expect(dates, hasLength(2));
    expect(dates[0].start, DateTime.utc(2026, 10, 4, 4));
    expect(dates[1].start, DateTime.utc(2026, 10, 10, 9, 30));
    expect(
      EventEligibility.registrationDates('2026/10/10 ~ 2026/10/01'),
      isEmpty,
    );
    expect(
      EventEligibility.registrationDates('2026/02/30 ~ 2026/03/01'),
      isEmpty,
    );
  });

  test('favorites belong to one account and are kept in the vault', () async {
    final vault = MemoryVault();
    final session = CampusSession(vault: vault, platformCleanup: []);
    addTearDown(session.dispose);
    await session.enterDemo();
    final store = EventFavorites(session);
    expect(await store.set(['1', '2'], favorite: true), {'1', '2'});
    expect(await store.set(['1'], favorite: false), {'2'});
    expect(await store.load(), {'2'});
    session.account = 'someone-else';
    expect(await store.load(), isEmpty);
  });

  group('batch', () {
    late CampusSession session;
    setUp(() async {
      session = CampusSession(vault: MemoryVault(), platformCleanup: []);
      await session.enterDemo();
    });
    tearDown(() => session.dispose());

    testWidgets('checks first, sends only after confirm, one at a time', (
      tester,
    ) async {
      final actions = _Batch([event('3')])
        ..open = [event('1'), event('2', status: '已截止'), event('3')];
      await tester.pumpWidget(
        MaterialApp(
          theme: NiuTheme.light,
          home: EventBatchScreen(
            events: [event('1'), event('2'), event('3')],
            actions: actions,
            session: session,
            clock: () => noon,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(actions.calls, isEmpty);
      expect(find.text('確認報名 1 個活動'), findsOneWidget);
      expect(find.textContaining('已截止'), findsOneWidget);
      expect(find.textContaining('已報名'), findsWidgets);
      await tester.tap(find.text('確認報名 1 個活動'));
      await tester.pumpAndSettle();
      expect(actions.calls, ['register 1']);
      expect(find.text('成功'), findsOneWidget);
      expect(find.text('完成'), findsOneWidget);
    });

    testWidgets('an uncertain result is never resent in this login', (
      tester,
    ) async {
      final actions = _Batch()
        ..open = [event('1')]
        ..uncertain = true;
      Future<void> run() async {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(
          MaterialApp(
            theme: NiuTheme.light,
            home: EventBatchScreen(
              events: [event('1')],
              actions: actions,
              session: session,
              clock: () => noon,
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await run();
      await tester.tap(find.text('確認報名 1 個活動'));
      await tester.pumpAndSettle();
      expect(find.text('結果不明'), findsOneWidget);
      await run();
      expect(find.text('沒有可送出的活動'), findsOneWidget);
      expect(find.textContaining('結果不明'), findsOneWidget);
      expect(actions.calls, ['register 1']);
    });

    testWidgets('select from the list, star, then register together', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final actions = _Batch()..open = [event('1'), event('2')];
      await tester.pumpWidget(
        MaterialApp(
          theme: NiuTheme.light,
          home: EventsScreen(
            session: session,
            actions: actions,
            loaderBuilder: (_, applied) =>
                SnapshotRoute(events: applied ? [] : actions.open),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('加入收藏').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('只看收藏'));
      await tester.pumpAndSettle();
      expect(find.text('活動 1'), findsOneWidget);
      expect(find.text('活動 2'), findsNothing);
      await tester.tap(find.text('只看收藏'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('選取活動'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('全選目前篩選'));
      await tester.pumpAndSettle();
      expect(find.text('已選 2 個活動'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '批次報名'));
      await tester.pumpAndSettle();
      expect(find.byType(EventBatchScreen), findsOneWidget);
    });
  });
}

class _Batch extends FakeEventActions {
  _Batch([super.mine]);
  bool uncertain = false;
  @override
  Future<EventActionResult> register(CampusEvent event) async {
    calls.add('register ${event.id}');
    return uncertain
        ? const EventActionResult(
            false,
            '學校系統回應逾時',
            needsWeb: true,
            uncertain: true,
          )
        : const EventActionResult(true, '報名成功');
  }
}
