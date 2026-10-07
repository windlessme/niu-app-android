import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/features/graduation/graduation_dashboard.dart';
import 'package:niu_mobile/features/graduation/graduation_screen.dart';
import 'package:niu_mobile/features/graduation/learning_hours.dart';
import 'package:niu_mobile/features/graduation/learning_hours_screen.dart';
import 'package:niu_mobile/shared/shared.dart';

import 'graduation_cache_test.dart' show graduationFixture;
import '../../support/fakes.dart';

const summaryJson =
    '{"IsSuccess":true,"Message":"","Data":['
    '{"AbilityId":"99","Ability":"綜合學習","CaHr":"0","TCaHr":0},'
    '{"AbilityId":1,"Ability":"服務奉獻","CaHr":2,"TCaHr":"20"},'
    '{"AbilityId":"3","Ability":"專業學習","CaHr":1.5,"TCaHr":8}]}';

String row(String start, String end, String title, String ability, String h) =>
    '<div class="learninghours__tbody-row">'
    '<div class="learninghours__td">$start</div>'
    '<div class="learninghours__td">$end</div>'
    '<div class="learninghours__td"><a href="#">$title</a></div>'
    '<div class="learninghours__td">$ability</div>'
    '<div class="learninghours__td">$h</div></div>';

String detailPage(List<String> rows, {int last = 1}) =>
    '<div>${rows.join()}</div><div id="page_html">'
    '${[for (var i = 1; i <= last; i++) '<a class="paging__btn" href="?page=$i">$i</a>'].join()}'
    '</div>';

class PortalAdapter implements HttpClientAdapter {
  PortalAdapter(this.reply);
  final Object Function(RequestOptions request) reply;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (requestStream != null) {
      options.extra['body'] = utf8.decode(
        await requestStream.expand((c) => c).toList(),
      );
    }
    final result = reply(options);
    if (result is Exception) throw result;
    if (result is ResponseBody) return result;
    return ResponseBody.fromString(result as String, 200);
  }

  @override
  void close({bool force = false}) {}
}

Dio Function() dioWith(PortalAdapter adapter) =>
    () => Dio(
      BaseOptions(
        responseType: ResponseType.plain,
        followRedirects: false,
        validateStatus: (_) => true,
      ),
    )..httpClientAdapter = adapter;

Object portal(RequestOptions request) => switch (request.uri.path) {
  '/login/student' => ResponseBody.fromString(
    '{"status":1}',
    200,
    headers: {
      'set-cookie': ['ep_session=abc123; path=/; HttpOnly'],
    },
  ),
  '/Api/MultLearn' => summaryJson,
  '/Api/MultLearnDetail' => switch (request.uri.queryParameters['page']) {
    '1' => detailPage([
      row('2026/9/3', '2026/9/3', '講座 &amp; 分享', '服務奉獻', '2'),
    ], last: 2),
    '2' => detailPage([
      row('2026/5/1', '2026/5/2', '工作坊', '專業學習', '1.5'),
    ], last: 2),
    _ => detailPage([], last: 2),
  },
  _ => ResponseBody.fromString('', 404),
};

void main() {
  group('parser', () {
    test('reads mixed strings and numbers in the graduation order', () {
      final summaries = LearningHoursParser.summary(summaryJson);
      expect(summaries.map((s) => s.abilityId), ['1', '3', '99']);
      expect(summaries.first.ability, '服務奉獻');
      expect(summaries.first.earned, 2);
      expect(summaries.first.required, 20);
      expect(summaries[1].earned, 1.5);
    });

    test('an array root means the portal session is gone', () {
      expect(
        () => LearningHoursParser.summary('[]'),
        throwsA(same(LearningHoursException.sessionExpired)),
      );
      expect(
        () =>
            LearningHoursParser.summary('{"IsSuccess":false,"Message":"維護中"}'),
        throwsA(
          isA<LearningHoursException>().having(
            (e) => e.message,
            'message',
            contains('維護中'),
          ),
        ),
      );
      expect(
        () => LearningHoursParser.summary('<html>'),
        throwsA(same(LearningHoursException.invalidResponse)),
      );
    });

    test('reads detail rows, entities and the last page', () {
      final page = LearningHoursParser.detail(
        detailPage([
          row(
            '2026/9/3',
            '2026/9/3',
            '講座&nbsp;&#21512;作 &amp; 分享',
            '服務奉獻',
            '2',
          ),
        ], last: 3),
      );
      expect(page.lastPage, 3);
      expect(page.records.single.title, '講座 合作 & 分享');
      expect(page.records.single.dates, '2026/9/3');
      expect(
        () => LearningHoursParser.detail(
          '<script>location.replace("/")</script>',
        ),
        throwsA(same(LearningHoursException.sessionExpired)),
      );
      expect(
        () => LearningHoursParser.detail('<div>no pager</div>'),
        throwsA(same(LearningHoursException.invalidResponse)),
      );
    });

    test('hours keep one decimal only when needed', () {
      expect(formatLearningHours(20), '20');
      expect(formatLearningHours(1.5), '1.5');
    });
  });

  group('client', () {
    test('signs in, keeps the cookie and reads every page', () async {
      final adapter = PortalAdapter(portal);
      final snapshot = await LearningHoursClient(
        dio: dioWith(adapter),
      ).fetch('b1234', 'p&ss');
      expect(snapshot.summaries, hasLength(3));
      expect(snapshot.records.map((r) => r.title), ['講座 & 分享', '工作坊']);
      expect(adapter.requests.first.extra['body'], contains('p%26ss'));
      for (final request in adapter.requests.skip(1)) {
        expect(request.headers['Cookie'], 'ep_session=abc123');
      }
    });

    test(
      'a rejected password and an unreachable portal map to messages',
      () async {
        final rejected = PortalAdapter((_) => '{"status":0}');
        await expectLater(
          LearningHoursClient(dio: dioWith(rejected)).fetch('b1', 'x'),
          throwsA(same(LearningHoursException.invalidCredentials)),
        );
        final unreachable = PortalAdapter(
          (r) => DioException.connectionError(requestOptions: r, reason: 'x'),
        );
        await expectLater(
          LearningHoursClient(dio: dioWith(unreachable)).fetch('b1', 'x'),
          throwsA(same(LearningHoursException.campusNetworkRequired)),
        );
        final forbidden = PortalAdapter(
          (_) => ResponseBody.fromString('', 403),
        );
        await expectLater(
          LearningHoursClient(dio: dioWith(forbidden)).fetch('b1', 'x'),
          throwsA(same(LearningHoursException.campusNetworkRequired)),
        );
      },
    );
  });

  group('store', () {
    late MemoryVault vault;
    late ScheduleSession session;
    setUp(() {
      vault = MemoryVault();
      session = ScheduleSession(vault)..account = 'b1234';
    });
    tearDown(() => session.dispose());

    test(
      'refresh uses the remembered password and caches per account',
      () async {
        vault.values['rememberedSchoolLogin'] = jsonEncode({
          'version': 1,
          'account': 'b1234',
          'password': 'secret',
        });
        final store = LearningHoursStore(
          session,
          client: LearningHoursClient(dio: dioWith(PortalAdapter(portal))),
        );
        expect(await store.cached(), isNull);
        final fresh = await store.refresh();
        expect(fresh!.records, hasLength(2));
        expect(
          jsonDecode(vault.values['learningHoursCache']!)['account'],
          'b1234',
        );
        expect((await store.cached())!.records.last.hours, '1.5');
        session.account = 'b9999';
        expect(await store.cached(), isNull);
      },
    );

    test('no remembered password asks to sign in again', () async {
      final store = LearningHoursStore(session);
      await expectLater(
        store.refresh(),
        throwsA(same(LearningHoursException.credentialsMissing)),
      );
    });
  });

  group('screens', () {
    testWidgets('the graduation card opens the record list', (tester) async {
      var opened = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: NiuTheme.light,
          home: Scaffold(
            body: GraduationDashboard(
              data: GraduationData.fromJson(graduationFixture()),
              onLearningHours: () => opened++,
            ),
          ),
        ),
      );
      await tester.tap(find.text('時數紀錄'));
      expect(opened, 1);
    });

    for (final dark in [false, true]) {
      testWidgets('demo records filter by domain dark=$dark at 320/2', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final session = ScheduleSession(MemoryVault())
          ..account = 'demo'
          ..isDemo = true;
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
            home: LearningHoursScreen(session: session),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('全部・4 筆'), findsOneWidget);
        await tester.ensureVisible(find.text('專業學習').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('專業學習').first);
        await tester.pumpAndSettle();
        expect(find.text('專業學習・1 筆'), findsOneWidget);
        expect(find.text('資訊安全實務工作坊'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
