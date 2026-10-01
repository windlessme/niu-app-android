import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/core/session/campus_session.dart';
import 'package:niu_mobile/core/time/campus_date.dart';
import 'package:niu_mobile/features/demo/demo_services.dart';
import 'package:niu_mobile/features/library/library_space_screen.dart';
import 'package:niu_mobile/features/library/library_space_session.dart';
import 'package:niu_mobile/features/library/space_models.dart';
import 'package:niu_mobile/features/library/webpac_client.dart';
import 'package:niu_mobile/shared/shared.dart';
import 'package:pointycastle/export.dart';

import 'features/authentication_session_test.dart' show MemoryVault;

/// Replays the library site: one HTML page plus GraphQL by operation text.
class WebpacAdapter implements HttpClientAdapter {
  WebpacAdapter(this.graphql, {this.signedIn = true});
  final Object? Function(String query, Map variables) graphql;
  bool signedIn;
  int forbiddenOnce = 0;
  final queries = <String>[];
  final cookies = <String?>[];
  final tokens = <String?>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    cookies.add(options.headers['Cookie'] as String?);
    if (options.method == 'GET') {
      return ResponseBody.fromString(
        '<script>{"session":{"csrfToken":"tok-${cookies.length}"},'
        '"auth":$signedIn}</script>',
        200,
        headers: {
          'set-cookie': ['HYSESSION=s%3Afresh; Path=/; HttpOnly'],
        },
      );
    }
    tokens.add(options.headers['X-CSRF-Token'] as String?);
    if (forbiddenOnce > 0) {
      forbiddenOnce--;
      return ResponseBody.fromString('forbidden', 403);
    }
    final bytes = await requestStream!.expand((c) => c).toList();
    final body = jsonDecode(utf8.decode(bytes)) as Map;
    queries.add(body['query'] as String);
    return ResponseBody.fromString(
      jsonEncode({
        'data': graphql(body['query'] as String, body['variables'] as Map),
      }),
      200,
    );
  }

  @override
  void close({bool force = false}) {}
}

WebpacClient client(WebpacAdapter adapter, {String? session = 'saved'}) =>
    WebpacClient()
      ..session = session
      ..dio.httpClientAdapter = adapter;

void main() {
  test('credentials are encrypted like the site login form', () {
    final iv = Uint8List.fromList(List.generate(16, (i) => i));
    expect(
      encryptCredential('b1234567', iv: iv),
      '000102030405060708090a0b0c0d0e0f:cTotEybLymaND/qf/dQeWA==',
    );
    final random = encryptCredential('密碼 secret').split(':');
    expect(random[0], hasLength(32));
    final cipher =
        PaddedBlockCipherImpl(
          PKCS7Padding(),
          CBCBlockCipher(AESEngine()),
        )..init(
          false,
          PaddedBlockCipherParameters<CipherParameters, CipherParameters>(
            ParametersWithIV(
              KeyParameter(
                Uint8List.fromList([
                  for (var i = 0; i < 64; i += 2)
                    int.parse(
                      'a20b070dfdf921334a47ee5c076106068c718f11e97e4835e08acf19b6728684'
                          .substring(i, i + 2),
                      radix: 16,
                    ),
                ]),
              ),
              Uint8List.fromList([
                for (var i = 0; i < 32; i += 2)
                  int.parse(random[0].substring(i, i + 2), radix: 16),
              ]),
            ),
            null,
          ),
        );
    expect(utf8.decode(cipher.process(base64.decode(random[1]))), '密碼 secret');
  });

  test('rules, multi-day bookings and free stretches', () {
    final rules = SpaceRules.parse(
      '{"canReserveMinUnit":"1.0","canReserveTotalUnit":"28.0","inReserve":"2.0",'
      '"closeTime":"21:30","openTime":"08:30","canReserveMaxUnit":"4.0"}',
    );
    expect(rules.open, 8 * 60 + 30);
    expect(rules.close, 21 * 60 + 30);
    expect(rules.minMinutes, 60);
    expect(rules.maxMinutes, 240);
    expect(rules.remainingHours, 26);

    final date = CampusDate(2026, 10, 2);
    final long = SpaceDay.clip(
      date,
      60,
      '2026-09-29 14:00:00.0',
      '2026-10-08 21:30:00.0',
      false,
    )!;
    expect((long.start, long.end), (0, 24 * 60));
    expect(
      SpaceDay.clip(
        date,
        60,
        '2026-10-03 08:00:00.0',
        '2026-10-03 09:00:00.0',
        false,
      ),
      isNull,
    );

    final day = SpaceDay(
      group: const SpaceGroup(8, '臨時研究小間'),
      date: date,
      rooms: const [SpaceRoom(67, '510研究小間')],
      bookings: const [
        SpaceBooking(roomId: 67, start: 13 * 60, end: 17 * 60),
        SpaceBooking(roomId: 67, start: 17 * 60 + 30, end: 18 * 60),
      ],
      rules: rules,
    );
    String show(List<(int, int)> list) => list
        .map((f) => '${formatMinute(f.$1)}-${formatMinute(f.$2)}')
        .join(',');
    expect(show(freeIntervals(day, 67)), '08:30-13:00,18:00-21:30');
    expect(
      show(freeIntervals(day, 67, min: 30)),
      '08:30-13:00,17:00-17:30,18:00-21:30',
    );
    expect(show(freeIntervals(day, 67, earliest: 19 * 60)), '19:00-21:30');
    expect(day.isFree(67, 12 * 60, 13 * 60), isTrue);
    expect(day.isFree(67, 12 * 60, 13 * 60 + 30), isFalse);
  });

  test('failure keys read as sentences', () {
    expect(
      describeReserveFailure('common:cir.eqReserve.failed.timeGroupDup'),
      '同一時段已預約了同類空間。',
    );
    expect(describeReserveFailure('common:label.unknown'), '預約沒有成功，請換個時段再試。');
    expect(describeReserveFailure('設備已停用'), '設備已停用');
  });

  test('day lists rooms, bookings and the group policy', () async {
    final adapter = WebpacAdapter((query, variables) {
      if (query.contains('getDayReservedByReader')) {
        expect(variables['q'], 63);
        return {
          'getDayReservedByReader': {
            'success': true,
            'data':
                '{"canReserveMinUnit":"1.0","canReserveMaxUnit":"4.0",'
                '"openTime":"08:30","closeTime":"21:30"}',
          },
        };
      }
      expect(variables, {'g': 10, 'd': '2026/10/02'});
      return {
        'getEquipmentInfoList': {
          'eqgroupitemlist': [
            {
              'equipment': {'id': 63, 'name': '523討論室'},
            },
            {
              'equipment': {'id': 64, 'name': '612討論室 '},
            },
          ],
        },
        'getReserveEquipmentList': {
          'eqgroupitemlist': [
            for (var i = 0; i < 2; i++)
              {
                'reserveCountByUser': 1,
                'equipmentCir': {
                  'equipmentId': 64,
                  'startDate': '2026-10-02 10:00:00.0',
                  'endDate': '2026-10-02 11:00:00.0',
                },
              },
          ],
        },
      };
    });
    final day = await client(
      adapter,
    ).day(const SpaceGroup(10, '大型討論室'), CampusDate(2026, 10, 2));
    expect(day.rooms.map((r) => r.name), ['523討論室', '612討論室']);
    expect(day.bookings, hasLength(1));
    expect(day.bookings.single.mine, isTrue);
    expect(day.rules.open, 8 * 60 + 30);
    expect(adapter.cookies.first, 'HYSESSION=saved');
  });

  test('groups without a reader policy are not offered', () async {
    final adapter = WebpacAdapter(
      (_, _) => {
        'getEquipmentGroupInfo': {
          'eqgroupitemlist': [
            {
              'equipmentGroup': {'id': 5, 'name': '宜思智慧小間', 'webpacDisplay': 1},
              'ebPolicy': {'id': 5},
            },
            {
              'equipmentGroup': {
                'id': 7,
                'name': '長期研究小間511',
                'webpacDisplay': 1,
              },
              'ebPolicy': null,
            },
            {
              'equipmentGroup': {'id': 9, 'name': '隱藏', 'webpacDisplay': 0},
              'ebPolicy': {'id': 9},
            },
          ],
        },
      },
    );
    expect((await client(adapter).groups()).map((g) => g.name), ['宜思智慧小間']);
  });

  test('reserve sends the site format and explains refusals', () async {
    Map? sent;
    final adapter = WebpacAdapter((query, variables) {
      sent = variables;
      return {
        'reserveEquipmentCir': {
          'success': false,
          'message': 'common:cir.eqReserve.failed.baseUnitsLT',
        },
      };
    });
    final web = client(adapter);
    await expectLater(
      web.reserve(
        const SpaceGroup(10, '大型討論室'),
        const SpaceRoom(63, '523討論室'),
        CampusDate(2026, 10, 2),
        10 * 60,
        15 * 60,
      ),
      throwsA(
        isA<SpaceException>().having(
          (e) => e.message,
          'message',
          '超過單次可預約的時數上限。',
        ),
      ),
    );
    expect(sent, {
      's': '2026/10/02 10:00',
      'e': '2026/10/02 15:00',
      'q': 63,
      'g': 10,
    });
  });

  test('a stale CSRF token is refreshed once', () async {
    final adapter = WebpacAdapter(
      (_, _) => {
        'reserve': {'success': false},
        'borrow': {'success': false},
      },
    )..forbiddenOnce = 1;
    expect(await client(adapter).mine(), isEmpty);
    expect(adapter.tokens, ['tok-1', 'tok-3']);
  });

  test('my reservations and cancelling by content id', () async {
    Map? cancelled;
    final adapter = WebpacAdapter((query, variables) {
      if (query.contains('cancelEquipmentCir')) {
        cancelled = variables;
        return {
          'cancelEquipmentCir': {'success': true, 'message': '設備取取消成功。'},
        };
      }
      return {
        'reserve': {
          'success': true,
          'eqgroupitemlist': [
            {
              'equipment': {'name': '523討論室'},
              'equipmentCir': {'reserveKeepDate': '2026-10-02 10:15:00.0'},
              'equipmentCirContent': {
                'id': 26762,
                'startDate': '2026-10-02 10:00:00.0',
                'endDate': '2026-10-02 11:00:00.0',
              },
            },
          ],
        },
        'borrow': {'success': false, 'eqgroupitemlist': []},
      };
    });
    final web = client(adapter);
    final list = await web.mine();
    expect(list.single.id, 26762);
    expect(list.single.keepUntil, 10 * 60 + 15);
    expect(list.single.state, ReservationState.reserved);
    await web.cancel(list.single);
    expect(cancelled, {'i': 26762});
  });

  test('session restore requires the same account and a live login', () async {
    final vault = MemoryVault();
    final session = CampusSession(vault: vault, platformCleanup: [])
      ..account = 'b123';
    addTearDown(session.dispose);
    final adapter = WebpacAdapter((_, _) => null);
    LibrarySpaceSession store() => LibrarySpaceSession(
      session,
      client: () => client(adapter, session: null),
    );

    expect(await store().restore(), isNull);
    await vault.write(
      LibrarySpaceSession.key,
      jsonEncode({'account': 'b999', 'session': 'other'}),
    );
    expect(await store().restore(), isNull);
    await vault.write(
      LibrarySpaceSession.key,
      jsonEncode({'account': 'b123', 'session': 'mine'}),
    );
    expect(await store().restore(), isNotNull);
    expect(adapter.cookies.last, 'HYSESSION=mine');
    adapter.signedIn = false;
    expect(await store().restore(), isNull);
  });

  testWidgets('demo: pick a free stretch, book it, then cancel it', (
    tester,
  ) async {
    final session = CampusSession(vault: MemoryVault(), platformCleanup: [])
      ..account = 'b123';
    addTearDown(session.dispose);
    // 2026-10-01 07:00 Taipei: every slot of the day is still ahead.
    DateTime now() => DateTime.utc(2026, 9, 30, 23);
    await tester.pumpWidget(
      MaterialApp(
        theme: NiuTheme.light,
        home: LibrarySpaceScreen(
          session: session,
          service: DemoSpaceService(now: now),
          now: now,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('預約空間'), findsOneWidget);
    expect(find.text('我的預約'), findsNothing);
    expect(find.text('今天 10/1（四）'), findsOneWidget);
    expect(find.text('iSmart 504'), findsOneWidget);

    await tester.tap(find.byType(ActionChip).first);
    await tester.pumpAndSettle();
    final confirm = find.textContaining(RegExp(r'^預約 \d\d:\d\d–\d\d:\d\d$'));
    expect(confirm, findsOneWidget);
    final label = tester.widget<Text>(confirm).data!;
    await tester.tap(confirm);
    await tester.pumpAndSettle();

    expect(find.text('我的預約'), findsOneWidget);
    expect(find.textContaining(label.substring(3)), findsWidgets);
    await tester.tap(find.widgetWithText(TextButton, '取消預約'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '取消預約'));
    await tester.pumpAndSettle();
    expect(find.text('我的預約'), findsNothing);
  });
}
