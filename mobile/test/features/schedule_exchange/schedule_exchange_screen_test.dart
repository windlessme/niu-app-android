import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/core/session/cached_schedule.dart';
import 'package:niu_mobile/features/schedule/schedule_models.dart';
import 'package:niu_mobile/features/schedule_exchange/my_schedule_code_screen.dart';
import 'package:niu_mobile/features/schedule_exchange/schedule_exchange_screen.dart';
import 'package:niu_mobile/features/schedule_exchange/schedule_exchange_store.dart';
import 'package:niu_mobile/features/schedule_exchange/schedule_share.dart';
import 'package:qr/qr.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fakes.dart' as fakes;
import 'schedule_exchange_store_test.dart' show MemoryVault;

const header = ['節次', '時間', '星期一', '星期二', '星期三', '星期四', '星期五'];
final myRows = [
  header,
  ['1', '08:10~09:00', '王老師\n微積分\nA101', '', '', '', ''],
  ['2', '09:10~10:00', '', '', '', '', ''],
  ['3', '10:10~11:00', '', '', '', '', '李老師\n英文\nB202'],
];

ScheduleSharePayload classmate() => ScheduleSharePayload.fromSchedule(
  ClassSchedule.fromRows([
    header,
    ['1', '08:10~09:00', '', '經濟學', '', '', ''],
    ['2', '09:10~10:00', '經濟學', '', '', '', ''],
    ['3', '10:10~11:00', '', '', '', '', ''],
  ]),
  shareId: ScheduleSharePayload.newShareId(),
  term: ScheduleShareTerm.containing(DateTime.now()),
  nickname: '小安',
  createdAt: DateTime.now(),
);

void main() {
  qrLevels();
  late fakes.ScheduleSession session;
  late ScheduleExchangeStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    session = fakes.ScheduleSession(fakes.MemoryVault())
      ..account = 'b123'
      ..cachedSchedule = CachedSchedule(
        account: 'b123',
        fetchedAt: DateTime.utc(2026, 10, 20),
        rows: myRows,
      );
    store = ScheduleExchangeStore(MemoryVault());
    await store.reload('b123');
  });

  Future<void> open(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: screen));
    await tester.pumpAndSettle();
  }

  testWidgets('hub explains the exchange before anyone is added', (
    tester,
  ) async {
    await open(tester, ScheduleExchangeScreen(session: session, store: store));
    expect(find.text('和同學交換課表'), findsOneWidget);
    expect(find.text('掃描'), findsOneWidget);
    expect(find.text('我的 QR Code'), findsOneWidget);
    expect(find.text('找共同空堂'), findsNothing);
  });

  testWidgets('hub lists classmates and opens their timetable', (tester) async {
    await tester.runAsync(() => store.save('b123', classmate()));
    await open(tester, ScheduleExchangeScreen(session: session, store: store));
    expect(find.text('小安'), findsOneWidget);
    expect(find.text('1 門課'), findsOneWidget);
    expect(find.text('找共同空堂'), findsOneWidget);

    await tester.tap(find.text('小安'));
    await tester.pumpAndSettle();
    expect(find.text('小安 的課表'), findsOneWidget);
    expect(find.text('標出我們都沒課的時間'), findsOneWidget);
    // Mon: 1 me, 2 them; Tue: 1 them; Fri: 3 me. Rows 1–3 are compared.
    await tester.scrollUntilVisible(find.text('都沒課的時間'), 300);
    expect(find.text('週二・第 2–3 節・9:10–11:00'), findsOneWidget);
    expect(find.text('週一・第 3 節・10:10–11:00'), findsOneWidget);
    expect(find.textContaining('週五'), findsWidgets);
  });

  testWidgets('a group comparison shows everyone free', (tester) async {
    final id = await tester.runAsync(() => store.save('b123', classmate()));
    await open(
      tester,
      GroupCompareScreen(ids: {id!}, session: session, store: store),
    );
    expect(find.text('2 人一起比對'), findsOneWidget);
    expect(find.text('我、小安'), findsOneWidget);
    expect(find.bySemanticsLabel('週三第 1 節，2 人中 2 人有空'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('都沒課的時間'), 300);
    expect(find.text('週二・第 2–3 節・9:10–11:00'), findsOneWidget);
  });

  testWidgets('a period lists who is free, and a name shows their times', (
    tester,
  ) async {
    final id = await tester.runAsync(() => store.save('b123', classmate()));
    await open(
      tester,
      GroupCompareScreen(ids: {id!}, session: session, store: store),
    );
    // Monday period 1: I have 微積分, 小安 is free.
    await tester.tap(find.bySemanticsLabel('週一第 1 節，2 人中 1 人有空'));
    await tester.pumpAndSettle();
    expect(find.text('週一・第 1 節・8:10–9:00'), findsOneWidget);
    expect(find.text('2 人中 1 人有空'), findsOneWidget);
    expect(find.text('我・微積分'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilterChip, '小安'));
    await tester.pumpAndSettle();
    expect(find.text('正在看：小安'), findsOneWidget);
    // Five days of three periods, less their two classes.
    expect(find.text('13 節有空'), findsOneWidget);
    await tester.tap(find.text('看全部'));
    await tester.pumpAndSettle();
    expect(find.text('正在看：小安'), findsNothing);
  });

  testWidgets('my code asks for a name first, then shows the code', (
    tester,
  ) async {
    session.profile = {'chName': '王小明'};
    await open(tester, MyScheduleCodeScreen(session: session, store: store));
    expect(find.text('同學會看到什麼名字？'), findsOneWidget);
    await tester.tap(find.text('改用真實姓名「王小明」'));
    // The store was opened outside the test's fake clock.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(find.text('王小明'), findsOneWidget);
    expect(find.bySemanticsLabel('我的課表 QR Code'), findsOneWidget);
    expect(find.text('傳送圖片'), findsOneWidget);
    expect(store.preferences.useRealName, isTrue);
  });
}

void qrLevels() {
  test('a logo only where the error correction can restore it', () {
    // Lengths of a typical table and of the 1800-character worst case.
    final small = ScheduleQr('NIUTT1:${'A' * 550}');
    expect(small.logo, isTrue);
    expect(small.image.errorCorrectLevel, QrErrorCorrectLevel.H);
    final hole = small.logoModules!;
    expect(hole.start * 2 + hole.size, small.image.moduleCount);
    expect(hole.size / small.image.moduleCount, closeTo(.22, .02));

    final large = ScheduleQr('NIUTT1:${'A' * 1793}');
    expect(large.logo, isFalse);
    expect(large.image.errorCorrectLevel, QrErrorCorrectLevel.M);
    expect(large.logoModules, isNull);
  });
}
