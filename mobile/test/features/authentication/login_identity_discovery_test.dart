import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/core/network/school_clients.dart';
import 'package:niu_mobile/core/session/campus_session.dart';
import 'package:niu_mobile/core/session/session_coordinator.dart';
import '../../support/fakes.dart';

class IdentityAdapter implements HttpClientAdapter {
  final requested = Completer<void>();
  final response = Completer<ResponseBody Function()>();
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (!requested.isCompleted) requested.complete();
    return (await response.future)();
  }

  void reply(Object? data, {int status = 200}) {
    response.complete(
      () => ResponseBody.fromString(
        jsonEncode({'data': data}),
        status,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      ),
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late IdentityAdapter adapter;
  late MemoryVault vault;
  late CampusSession session;
  setUp(() {
    adapter = IdentityAdapter();
    vault = MemoryVault();
    final http = schoolClient('https://ccsys1.niu.edu.tw')
      ..httpClientAdapter = adapter;
    session = CampusSession(
      vault: vault,
      sso: SsoApiClient(http),
      platformCleanup: [],
    );
    addTearDown(http.close);
  });

  test(
    'token alone discovers server identity and completes normal verification',
    () async {
      // No username DOM or input survives the redirect; even a token claiming a
      // different account must use the identity returned by the school server.
      final claims = base64Url.encode(utf8.encode('{"acnt":"attacker"}'));
      final token = 'header.$claims.signature';
      adapter.reply({'acnt': ' B123 ', 'chName': '測試同學'});
      await session.acceptToken(token, null);
      expect(session.account, 'b123');
      expect(session.displayName, '測試同學');
      expect(vault.values['ssoAccount'], 'b123');
      expect(vault.values['ssoToken'], token);
      expect(adapter.requests, hasLength(2));
      for (final request in adapter.requests) {
        expect(
          request.uri.toString(),
          'https://ccsys1.niu.edu.tw/SSO/API/Authorization/info',
        );
        expect(request.headers['Authorization'], 'Bearer $token');
        expect(request.followRedirects, false);
      }
    },
  );

  for (final account in [null, '', '   ', 123]) {
    test(
      'missing or malformed server account $account cannot sign in',
      () async {
        adapter.reply({'acnt': account});
        await expectLater(
          session.acceptToken('token', null),
          throwsA(isA<SchoolApiException>()),
        );
        expect(session.isSignedIn, false);
        expect(vault.values, isEmpty);
      },
    );
  }

  test('unauthorized info response cannot discover identity', () async {
    adapter.reply({'acnt': 'b123'}, status: 401);
    await expectLater(
      session.acceptToken('token', null),
      throwsA(isA<DioException>()),
    );
    expect(vault.values, isEmpty);
    expect(session.isSignedIn, false);
  });

  test('discovery cannot replace a persisted account before logout', () async {
    vault.values.addAll({'ssoAccount': 'b456', 'ssoToken': 'old'});
    adapter.reply({'acnt': 'b123'});
    await expectLater(session.acceptToken('token', null), throwsStateError);
    expect(vault.values, {'ssoAccount': 'b456', 'ssoToken': 'old'});
    expect(session.isSignedIn, false);
  });

  test(
    'logout during discovery prevents late identity from restoring session',
    () async {
      final attempt = session.acceptToken('token', null);
      final expectation = expectLater(attempt, throwsA(isA<SessionChanged>()));
      await adapter.requested.future;
      await session.logout();
      adapter.reply({'acnt': 'b123'});
      await expectation;
      expect(session.isSignedIn, false);
      expect(vault.values.keys, isNot(contains('ssoToken')));
      expect(adapter.requests, hasLength(1));
    },
  );
}
