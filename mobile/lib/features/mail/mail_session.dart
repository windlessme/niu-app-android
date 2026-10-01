import 'dart:convert';
import 'dart:typed_data';

import '../../core/session/campus_session.dart';
import '../../core/session/session_coordinator.dart';
import 'mail_captcha.dart';
import 'mail_models.dart';
import 'numail_client.dart';

/// One sign-in attempt: a fresh client and the code it was issued.
class MailChallenge {
  MailChallenge(this.client, this.png, this.guess);
  final NumailClient client;

  /// Rendered code, or null when the site asks for none.
  final Uint8List? png;

  /// What on-device recognition read, if anything.
  final String? guess;
}

/// Keeps the NUMail session for the signed-in student. Only the cookie
/// envelope is saved; the password lives just for the length of a sign-in.
class MailSession {
  MailSession(
    this.owner, {
    NumailClient Function(Map<String, String>? cookies)? client,
    CaptchaReader? reader,
  }) : client = client ?? ((cookies) => NumailClient(cookies: cookies)),
       reader = reader ?? readCaptcha;
  static const key = 'mailSession';
  final CampusSession owner;
  final NumailClient Function(Map<String, String>? cookies) client;
  final CaptchaReader reader;

  String? get _account => owner.account;

  void _guard(int epoch, String account) {
    owner.coordinator.requireCurrent(epoch);
    if (!owner.hasLocalAccount || owner.account != account) {
      throw SessionChanged();
    }
  }

  /// A client whose saved session NUMail still accepts, else null.
  Future<NumailClient?> restore() async {
    final account = _account;
    if (!owner.hasLocalAccount || account == null) return null;
    final epoch = owner.coordinator.epoch;
    final raw = await owner.vault.read(key);
    _guard(epoch, account);
    if (raw == null || raw.isEmpty) return null;
    final Map data;
    try {
      data = jsonDecode(raw) as Map;
    } catch (_) {
      return null;
    }
    if (data['account'] != account || data['cookies'] is! Map) return null;
    final web = client({
      for (final e in (data['cookies'] as Map).entries)
        '${e.key}': '${e.value}',
    });
    try {
      final who = await web.signedInAs();
      _guard(epoch, account);
      if (who != null && who.toLowerCase() == account) return web;
    } catch (_) {
      web.close();
      rethrow;
    }
    web.close();
    return null;
  }

  /// Starts a sign-in and tries to read its code on the device.
  Future<MailChallenge> challenge() async {
    final web = client(null);
    try {
      final svg = await web.captcha();
      if (svg == null) return MailChallenge(web, null, null);
      final png = await CaptchaShape.parse(svg).png();
      String? guess;
      try {
        guess = await reader(png);
      } catch (_) {}
      return MailChallenge(web, png, guess);
    } catch (_) {
      web.close();
      rethrow;
    }
  }

  /// Completes [challenge] and saves the session.
  Future<NumailClient> signIn(
    MailChallenge challenge,
    String password,
    String code,
  ) async {
    final account = _account;
    if (account == null) throw SessionChanged();
    final epoch = owner.coordinator.epoch;
    await owner.coordinator.authenticate(CampusService.mail, (_) async {
      await challenge.client.login(account, password, code.trim());
      _guard(epoch, account);
    });
    await save(challenge.client);
    return challenge.client;
  }

  Future<NumailClient> twoFactor(MailChallenge challenge, String code) async {
    final account = _account;
    if (account == null) throw SessionChanged();
    await challenge.client.twoFactor(account, code);
    await save(challenge.client);
    return challenge.client;
  }

  Future<void> save(NumailClient web) async {
    final account = _account;
    if (account == null) throw SessionChanged();
    final epoch = owner.coordinator.epoch;
    await owner.vault.write(
      key,
      jsonEncode({'account': account, 'cookies': web.cookies}),
    );
    _guard(epoch, account);
  }

  /// Signs in without asking: up to three codes read on the device. Wrong
  /// passwords and extra verification stop at once.
  Future<NumailClient?> automatic(String password) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      final next = await challenge();
      if (next.png != null && next.guess == null) {
        next.client.close();
        continue;
      }
      try {
        return await signIn(next, password, next.guess ?? '');
      } on MailWrongCaptcha {
        next.client.close();
      } catch (_) {
        next.client.close();
        rethrow;
      }
    }
    return null;
  }

  /// Mail sign-in failing must never fail the school login itself.
  static Future<void> establishQuietly(
    CampusSession owner,
    String account,
    String password,
  ) async {
    if (owner.account != account.trim().toLowerCase()) return;
    try {
      (await MailSession(owner).automatic(password))?.close();
    } catch (_) {}
  }
}
