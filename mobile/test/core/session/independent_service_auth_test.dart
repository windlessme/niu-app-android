import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/core/network/school_clients.dart';
import 'package:niu_mobile/core/session/campus_session.dart';
import 'package:niu_mobile/features/events/event_login_service.dart';
import 'package:niu_mobile/features/events/event_portal.dart';
import 'package:niu_mobile/features/moodle/moodle_login_service.dart';
import 'package:niu_mobile/features/moodle/moodle_session_store.dart';
import '../../support/fakes.dart';

void main() {
  test(
    'Moodle restores and reads with expired SSO, but logout revokes it',
    () async {
      final vault = MemoryVault()
        ..values['moodleSession'] = jsonEncode({
          'account': 'b123',
          'token': 'moodle-token',
          'privateToken': 'private-token',
          'userId': 7,
        });
      final owner = CampusSession(vault: vault, platformCleanup: [])
        ..account = 'b123'
        ..ssoNeedsReauthentication = true;
      expect(owner.isSignedIn, false);
      expect(owner.hasLocalAccount, true);
      final adapter = WireAdapter(
        (request) =>
            Uri.splitQueryString(
                  request.extra['wireBody'] as String,
                )['wsfunction'] ==
                'core_webservice_get_site_info'
            ? {'userid': 7, 'username': 'b123'}
            : [],
      );
      final api = MoodleApiClient(
        schoolClient('https://euni.niu.edu.tw')..httpClientAdapter = adapter,
      );
      final repo = await MoodleLoginService(owner, api: api).restore();
      expect(repo, isNotNull);
      expect(await repo!.courses(), isEmpty);
      expect(adapter.requests.length, 2);
      await owner.logout();
      expect(owner.hasLocalAccount, false);
      await expectLater(repo.courses(), throwsA(anything));
      expect(await MoodleLoginService(owner, api: api).restore(), isNull);
      expect(adapter.requests.length, 2);
    },
  );

  test('local account does not authorize a new password handoff', () async {
    final owner = CampusSession(vault: MemoryVault(), platformCleanup: [])
      ..account = 'b123'
      ..ssoNeedsReauthentication = true;
    final adapter = WireAdapter((_) => throw StateError('unexpected request'));
    final service = MoodleLoginService(
      owner,
      api: MoodleApiClient(
        schoolClient('https://euni.niu.edu.tw')..httpClientAdapter = adapter,
      ),
    );
    await expectLater(
      service.establish(
        account: 'b123',
        password: 'password',
        epoch: owner.coordinator.epoch,
      ),
      throwsA(anything),
    );
    await expectLater(
      EventLoginService().establish(
        'b123',
        'password',
        owner,
        owner.coordinator.epoch,
      ),
      throwsA(anything),
    );
    expect(adapter.requests, isEmpty);
  });

  test(
    'local Moodle guard rejects changed accounts and pending cleanup',
    () async {
      final owner = CampusSession(vault: MemoryVault(), platformCleanup: [])
        ..account = 'b123';
      final store = MoodleSessionStore(owner);
      store.guard(owner.coordinator.epoch, 'b123');
      owner.account = 'other';
      expect(
        () => store.guard(owner.coordinator.epoch, 'b123'),
        throwsStateError,
      );
      owner.account = 'b123';
      owner.cleanupPending = true;
      expect(
        () => store.guard(owner.coordinator.epoch, 'b123'),
        throwsStateError,
      );
      await expectLater(eventPortalEntry(owner), throwsStateError);
      await store.dispose();
    },
  );

  test(
    'event cookies can restore with expired SSO, but not after logout',
    () async {
      final owner = CampusSession(vault: MemoryVault(), platformCleanup: [])
        ..account = 'b123'
        ..ssoNeedsReauthentication = true;
      expect(await eventPortalEntry(owner), eventListUri);
      await owner.logout();
      await expectLater(eventPortalEntry(owner), throwsStateError);
    },
  );
}
