import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/core/network/school_clients.dart';
import 'package:niu_mobile/core/session/campus_session.dart';
import 'package:niu_mobile/core/session/session_coordinator.dart';
import '../../support/fakes.dart';

void main() {
  test(
    'unverified token is not persisted or treated as authenticated',
    () async {
      final vault = MemoryVault();
      final api = FixtureSso();
      final session = CampusSession(vault: vault, sso: api);
      final attempt = session.acceptToken('fixture-token', 'B123');
      final expectation = expectLater(
        attempt,
        throwsA(isA<SchoolApiException>()),
      );
      expect(session.isSignedIn, false);
      expect(vault.values, isEmpty);
      await api.requested.future;
      api.result.completeError(
        const SchoolApiException('sso_identity_mismatch'),
      );
      await expectation;
      expect(vault.values, isEmpty);
    },
  );

  test(
    'late identity response after logout generation cannot repopulate credentials',
    () async {
      final vault = MemoryVault();
      final api = FixtureSso();
      final session = CampusSession(vault: vault, sso: api);
      final attempt = session.acceptToken('fixture-token', 'B123');
      final expectation = expectLater(attempt, throwsA(isA<SessionChanged>()));
      await api.requested.future;
      await session.coordinator.logout(vault.clear);
      api.result.complete({'acnt': 'b123', 'chName': '測試同學'});
      await expectation;
      expect(session.isSignedIn, false);
      expect(vault.values, isEmpty);
    },
  );

  test('verified identity is normalized and securely persisted', () async {
    final vault = MemoryVault();
    final api = FixtureSso();
    final session = CampusSession(vault: vault, sso: api);
    api.result.complete({'acnt': 'b123', 'chName': '測試同學'});
    await session.acceptToken('fixture-token', ' B123 ');
    expect(session.account, 'b123');
    expect(session.displayName, '測試同學');
    expect(vault.values['ssoAccount'], 'b123');
    expect(vault.values['ssoToken'], 'fixture-token');
    await expectLater(
      session.acceptToken('other-token', 'b456'),
      throwsStateError,
    );
  });
}
