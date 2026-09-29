import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/core/session/campus_session.dart';
import 'package:niu_mobile/core/storage/credential_vault.dart';
import 'package:niu_mobile/features/authentication/remember_school_login.dart';
import 'package:niu_mobile/features/authentication/school_login_capture.dart';

class _Vault implements CredentialVault {
  final values = <String, String>{};
  Completer<void>? gate;
  final started = Completer<void>();
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    if (key == RememberSchoolLogin.key && value.isNotEmpty && gate != null) {
      if (!started.isCompleted) started.complete();
      await gate!.future;
    }
    values[key] = value;
  }

  @override
  Future<void> clear() async => values.clear();
}

class _VerifiedSession extends CampusSession {
  _VerifiedSession(_Vault vault) : super(vault: vault, platformCleanup: []);
  @override
  bool get isSignedIn => account != null;
}

void main() {
  const credentials = SubmittedSchoolCredentials('b123', 'secret');

  test('explicit consent and matching verified identity required', () async {
    final vault = _Vault();
    final session = _VerifiedSession(vault);
    final service = RememberSchoolLogin.forSession(session);
    expect(service.enabled, isFalse);
    await service.saveVerified(credentials, epoch: 0, consentRevision: 0);
    expect(vault.values, isEmpty);
    await service.setEnabled(true);
    session.account = 'other';
    await service.saveVerified(
      credentials,
      epoch: 0,
      consentRevision: service.revision,
    );
    expect(vault.values, isEmpty);
    session.account = 'b123';
    await service.saveVerified(
      credentials,
      epoch: 0,
      consentRevision: service.revision,
    );
    expect(
      jsonDecode(vault.values[RememberSchoolLogin.key]!)['account'],
      'b123',
    );
    expect((await service.restore())!.password, 'secret');
    await service.forget();
    expect(await service.restore(), isNull);
  });

  test(
    'toggle off drains an in-flight save before clearing envelope',
    () async {
      final vault = _Vault()..gate = Completer<void>();
      final session = _VerifiedSession(vault)..account = 'b123';
      final service = RememberSchoolLogin.forSession(session);
      await service.setEnabled(true);
      final revision = service.revision;
      final saving = service.saveVerified(
        credentials,
        epoch: 0,
        consentRevision: revision,
      );
      await vault.started.future;
      final forgetting = service.forget();
      vault.gate!.complete();
      await saving;
      await forgetting;
      await service.setEnabled(true);
      await service.saveVerified(
        credentials,
        epoch: 0,
        consentRevision: revision,
      );
      expect(vault.values[RememberSchoolLogin.key], '');
    },
  );

  test(
    'session logout waits for writes before clearing remembered key',
    () async {
      final vault = _Vault()..gate = Completer<void>();
      final session = _VerifiedSession(vault)..account = 'b123';
      final service = RememberSchoolLogin.forSession(session);
      await service.setEnabled(true);
      final saving = service.saveVerified(
        credentials,
        epoch: 0,
        consentRevision: service.revision,
      );
      await vault.started.future;
      final logout = session.logout();
      vault.gate!.complete();
      await saving;
      await logout;
      expect(vault.values.containsKey(RememberSchoolLogin.key), isFalse);
      expect(service.enabled, isFalse);
    },
  );

  test('prefill permits only exact HTTPS login URL', () {
    expect(
      isSchoolLoginPage(Uri.parse('https://ccsys1.niu.edu.tw/SSO/login')),
      isTrue,
    );
    for (final url in [
      'http://ccsys1.niu.edu.tw/SSO/login',
      'https://ccsys1.niu.edu.tw.evil.test/SSO/login',
      'https://ccsys1.niu.edu.tw:444/SSO/login',
      'https://user@ccsys1.niu.edu.tw/SSO/login',
      'https://ccsys1.niu.edu.tw/SSO/login/',
      'https://ccsys1.niu.edu.tw/SSO/other',
    ]) {
      expect(isSchoolLoginPage(Uri.parse(url)), isFalse);
    }
  });
}
