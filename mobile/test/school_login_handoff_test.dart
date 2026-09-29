import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/core/network/school_clients.dart';
import 'package:niu_mobile/features/authentication/school_login_capture.dart';
import 'package:niu_mobile/features/moodle/moodle_login_service.dart';
import 'moodle_session_flow_test.dart' show MemoryVault, SignedSession;
import 'moodle_wire_test.dart' show WireAdapter;

void main() {
  test('capture rejects untrusted origins and capabilities', () {
    final message = {
      'capability': 'per-view-secret',
      'account': ' B123 ',
      'password': 'test-password',
    };
    SubmittedSchoolCredentials? parse(String page, String key) =>
        SubmittedSchoolCredentials.fromMessage(
          message,
          page: Uri.parse(page),
          capability: key,
        );
    expect(
      parse('https://ccsys1.niu.edu.tw/SSO/login', 'per-view-secret')!.account,
      'b123',
    );
    for (final page in [
      'http://ccsys1.niu.edu.tw/SSO/login',
      'https://ccsys1.niu.edu.tw.evil.test/SSO/login',
      'https://ccsys1.niu.edu.tw:8443/SSO/login',
      'https://user@ccsys1.niu.edu.tw/SSO/login',
    ]) {
      expect(parse(page, 'per-view-secret'), isNull);
    }
    expect(parse('https://ccsys1.niu.edu.tw/SSO/login', 'wrong'), isNull);
  });

  test(
    'verified SSO handoff persists tokens and restores without password',
    () async {
      final vault = MemoryVault();
      final owner = SignedSession(vault)..account = 'b123';
      final adapter = WireAdapter(
        (request) => request.path == '/login/token.php'
            ? {'token': 'api-token', 'privatetoken': 'private-token'}
            : {'userid': 7, 'username': 'b123'},
      );
      final service = MoodleLoginService(
        owner,
        api: MoodleApiClient(
          schoolClient('https://euni.niu.edu.tw')..httpClientAdapter = adapter,
        ),
      );
      await service.establish(
        account: 'B123',
        password: 'one-time-password',
        epoch: 0,
      );
      expect(vault.values.keys, ['moodleSession']);
      expect(vault.values.values.join(), isNot(contains('one-time-password')));
      final restored = await service.restore();
      expect(restored!.session.privateToken, 'private-token');
      expect(
        adapter.requests.where((r) => r.path == '/login/token.php').length,
        1,
      );
    },
  );

  test(
    'handoff rejects missing or mismatched verified SSO before sending password',
    () async {
      final owner = SignedSession(MemoryVault());
      final adapter = WireAdapter((_) => {});
      final service = MoodleLoginService(
        owner,
        api: MoodleApiClient(
          schoolClient('https://euni.niu.edu.tw')..httpClientAdapter = adapter,
        ),
      );
      await expectLater(
        service.establish(account: 'b123', password: 'p', epoch: 0),
        throwsStateError,
      );
      owner.account = 'other';
      await expectLater(
        service.establish(account: 'b123', password: 'p', epoch: 0),
        throwsStateError,
      );
      expect(adapter.requests, isEmpty);
    },
  );

  test(
    'logout during Moodle authentication prevents envelope resurrection',
    () async {
      final gate = Completer<void>();
      final started = Completer<void>();
      final vault = MemoryVault();
      final owner = SignedSession(vault)..account = 'b123';
      final service = MoodleLoginService(
        owner,
        api: _DelayedApi(gate, started),
      );
      final pending = service.establish(
        account: 'b123',
        password: 'p',
        epoch: 0,
      );
      final assertion = expectLater(pending, throwsA(anything));
      await started.future;
      await owner.coordinator.logout(() async {
        owner.account = null;
        await vault.clear();
      });
      gate.complete();
      await assertion;
      expect(vault.values, isEmpty);
    },
  );
}

class _DelayedApi extends MoodleApiClient {
  _DelayedApi(this.gate, this.started)
    : super(schoolClient('https://euni.niu.edu.tw'));
  final Completer<void> gate, started;
  @override
  Future<Map<String, dynamic>> authenticateSession(
    String username,
    String password,
  ) async {
    started.complete();
    await gate.future;
    return {'token': 't'};
  }

  @override
  Future<Object?> read(
    String token,
    String function,
    Map<String, Object> params,
  ) async => {'userid': 7, 'username': 'b123'};
}
