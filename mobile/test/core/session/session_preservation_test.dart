import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/core/network/school_clients.dart';
import 'package:niu_mobile/core/session/campus_session.dart';
import '../../support/fakes.dart';

class RestoreApi extends SsoApiClient {
  RestoreApi(this.verify) : super(schoolClient('https://ccsys1.niu.edu.tw'));
  final Future<Map<String, dynamic>> Function(String) verify;
  @override
  Future<Map<String, dynamic>> verifyIdentity(String token, String account) =>
      verify(token);
}

void main() {
  test('simultaneous reconnect checks share one request', () async {
    final gate = Completer<Map<String, dynamic>>();
    var requests = 0;
    final vault = MemoryVault()
      ..values.addAll({'ssoAccount': 'b123', 'ssoToken': 'saved'});
    final session = CampusSession(
      vault: vault,
      sso: RestoreApi((_) {
        requests++;
        return gate.future;
      }),
      platformCleanup: [],
    );
    final a = session.retryRestore();
    final b = session.retryRestore();
    expect(identical(a, b), isTrue);
    gate.complete({'acnt': 'b123'});
    await Future.wait([a, b]);
    expect(requests, 1);
    expect(session.isSignedIn, isTrue);
  });
  MemoryVault saved() => MemoryVault()
    ..values.addAll({
      'ssoAccount': 'b123',
      'ssoToken': 'old',
      'ssoProfile': jsonEncode({'chName': '同學'}),
      'moodleSession': 'moodle-envelope',
      'eventSession': 'event-cookie-envelope',
      'scheduleCache': jsonEncode({
        'account': 'b123',
        'fetchedAt': '2026-09-29T01:00:00Z',
        'rows': [
          ['節次', '時間', '星期二'],
        ],
      }),
    });
  test(
    'SSO 401 keeps other service credentials and cache without cleanup',
    () async {
      final vault = saved();
      final before = Map.of(vault.values);
      var clears = 0;
      final api = RestoreApi(
        (_) async => throw DioException(
          requestOptions: RequestOptions(),
          response: Response(requestOptions: RequestOptions(), statusCode: 401),
        ),
      );
      final session = CampusSession(
        vault: vault,
        sso: api,
        platformCleanup: [
          () async {
            clears++;
          },
        ],
      );
      await session.restore();
      expect(session.isSignedIn, false);
      expect(session.hasLocalAccount, true);
      expect(session.ssoNeedsReauthentication, true);
      expect(session.cachedSchedule, isNotNull);
      expect(vault.values, before);
      expect(clears, 0);
      await session.logout();
      expect(session.hasLocalAccount, false);
      expect(vault.values.keys, ['pendingCleanup']);
      expect(clears, 1);
    },
  );
  test(
    'malformed identity response preserves local identity as unavailable',
    () async {
      final vault = saved();
      final session = CampusSession(
        vault: vault,
        sso: RestoreApi(
          (_) async => throw const SchoolApiException('sso_identity_missing'),
        ),
        platformCleanup: [],
      );
      await session.restore();
      expect(session.isOffline, true);
      expect(session.ssoNeedsReauthentication, false);
      expect(vault.values['moodleSession'], 'moodle-envelope');
    },
  );
  test(
    'late startup rejection cannot overwrite a newly verified login',
    () async {
      final old = Completer<Map<String, dynamic>>();
      final started = Completer<void>();
      final session = CampusSession(
        vault: saved(),
        sso: RestoreApi((token) async {
          if (token == 'old') {
            started.complete();
            return old.future;
          }
          return {'acnt': 'b123', 'chName': '新登入'};
        }),
        platformCleanup: [],
      );
      final restore = session.restore();
      await started.future;
      await session.acceptToken('new', 'b123');
      old.completeError(const SchoolApiException('sso_identity_mismatch'));
      await restore;
      expect(session.isSignedIn, true);
      expect(session.displayName, '新登入');
      expect(session.ssoNeedsReauthentication, false);
    },
  );
}
