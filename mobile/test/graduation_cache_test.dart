import 'dart:async';
import 'dart:convert';

import 'package:niu_mobile/core/network/school_clients.dart';
import 'package:niu_mobile/core/session/cached_graduation.dart';
import 'package:niu_mobile/core/session/campus_session.dart';
import 'package:niu_mobile/core/session/session_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

import 'features/authentication_session_test.dart' show MemoryVault, FixtureSso;
import 'fresh_academic_session_test.dart' show FreshSso;

Map<String, dynamic> graduationFixture({String english = '通過'}) => {
  'diverseHours': ['10', '20', '30', '40'],
  'creditRequired': ['128', '90'],
  'englishAbility': english,
  'physicalFitness': '',
  'creditCourse': '',
};

class DelayedGraduationVault extends MemoryVault {
  final started = Completer<void>();
  final release = Completer<void>();
  @override
  Future<void> write(String key, String value) async {
    if (key == 'graduationCache') {
      started.complete();
      await release.future;
    }
    await super.write(key, value);
  }
}

void main() {
  test(
    'encrypted snapshot restores offline and after SSO expiry with unknowns intact',
    () async {
      for (final failure in [
        StateError('offline'),
        const SchoolApiException('sso_identity_mismatch'),
      ]) {
        final vault = MemoryVault();
        final session = CampusSession(
          vault: vault,
          sso: FreshSso(),
          platformCleanup: [],
        );
        await session.acceptToken('fixture', 'b123');
        await session.cacheGraduationData(
          graduationFixture(),
          epoch: 0,
          owner: 'b123',
        );
        final stamp = session.cachedGraduation!.fetchedAt;
        final api = FixtureSso();
        final restored = CampusSession(
          vault: vault,
          sso: api,
          platformCleanup: [],
        );
        final pending = restored.restore();
        await api.requested.future;
        api.result.completeError(failure);
        await pending;
        expect(restored.hasLocalAccount, isTrue);
        expect(restored.isSignedIn, isFalse);
        expect(restored.cachedGraduation!.fetchedAt, stamp);
        expect(restored.cachedGraduation!.data['physicalFitness'], '');
        expect(restored.cachedGraduation!.data, graduationFixture());
        await restored.logout();
        expect(restored.cachedGraduation, isNull);
        expect(vault.values['graduationCache'], isNull);
        restored.dispose();
        session.dispose();
      }
    },
  );

  test(
    'mismatched and damaged caches do not block login or become data',
    () async {
      final valid = CachedGraduation(
        account: 'b456',
        fetchedAt: DateTime.now(),
        data: graduationFixture(),
      ).toJson();
      for (final raw in [
        jsonEncode(valid),
        '{broken',
        jsonEncode({...valid, 'account': 'b123', 'version': 999}),
        jsonEncode({...valid, 'account': 'b123', 'fetchedAt': 'invalid'}),
        jsonEncode({
          ...valid,
          'account': 'b123',
          'data': {'creditRequired': 0},
        }),
      ]) {
        final vault = MemoryVault()
          ..values.addAll({
            'ssoAccount': 'b123',
            'ssoToken': 'fixture',
            'graduationCache': raw,
          });
        final session = CampusSession(vault: vault, sso: FreshSso());
        await session.restore();
        expect(session.isSignedIn, isTrue);
        expect(session.cachedGraduation, isNull);
        session.dispose();
      }
    },
  );

  test(
    'logout waits for an in-flight cache write and prevents resurrection',
    () async {
      final vault = DelayedGraduationVault();
      final session = CampusSession(
        vault: vault,
        sso: FreshSso(),
        platformCleanup: [],
      );
      await session.acceptToken('fixture', 'b123');
      final save = session.cacheGraduationData(
        graduationFixture(),
        epoch: 0,
        owner: 'b123',
      );
      final assertion = expectLater(save, throwsA(isA<SessionChanged>()));
      await vault.started.future;
      var loggedOut = false;
      final logout = session.logout().then((_) => loggedOut = true);
      await Future<void>.delayed(Duration.zero);
      expect(loggedOut, isFalse);
      expect(session.cachedGraduation, isNull);
      vault.release.complete();
      await assertion;
      await logout;
      expect(session.cachedGraduation, isNull);
      expect(vault.values['graduationCache'], isNull);
      session.dispose();
    },
  );

  test(
    'invalid response and wrong owner preserve the previous snapshot',
    () async {
      final vault = MemoryVault();
      final session = CampusSession(vault: vault, sso: FreshSso());
      await session.acceptToken('fixture', 'b123');
      await session.cacheGraduationData(
        graduationFixture(),
        epoch: 0,
        owner: 'b123',
      );
      final before = vault.values['graduationCache'];
      await expectLater(
        session.cacheGraduationData({}, epoch: 0, owner: 'b123'),
        throwsFormatException,
      );
      await expectLater(
        session.cacheGraduationData(
          graduationFixture(),
          epoch: 0,
          owner: 'other',
        ),
        throwsA(isA<SessionChanged>()),
      );
      expect(vault.values['graduationCache'], before);
      expect(session.cachedGraduation!.data, graduationFixture());
      session.dispose();
    },
  );

  test('late session restore cannot replace a freshly updated cache', () async {
    final vault = MemoryVault();
    final original = CampusSession(vault: vault, sso: FreshSso());
    await original.acceptToken('fixture', 'b123');
    await original.cacheGraduationData(
      graduationFixture(),
      epoch: 0,
      owner: 'b123',
    );
    final api = FixtureSso();
    final session = _RestoringSession(vault: vault, sso: api)..account = 'b123';
    final restore = session.restore();
    await api.requested.future;
    final updated = graduationFixture(english: '最新結果');
    await session.cacheGraduationData(updated, epoch: 0, owner: 'b123');
    api.result.complete({'acnt': 'b123'});
    await restore;
    expect(session.cachedGraduation!.data, updated);
    session.dispose();
    original.dispose();
  });
}

class _RestoringSession extends CampusSession {
  _RestoringSession({required super.vault, required super.sso});
  @override
  bool get isSignedIn => account != null;
}
