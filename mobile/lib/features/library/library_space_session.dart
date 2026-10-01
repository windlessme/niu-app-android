import 'dart:convert';

import '../../core/session/campus_session.dart';
import '../../core/session/session_coordinator.dart';
import 'webpac_client.dart';

/// Keeps the library's HYSESSION for the signed-in student. Only the cookie
/// envelope is saved; the password lives just for the length of a login.
class LibrarySpaceSession {
  LibrarySpaceSession(this.owner, {WebpacClient Function()? client})
    : client = client ?? WebpacClient.new;
  static const key = 'librarySession';
  final CampusSession owner;
  final WebpacClient Function() client;

  void _guard(int epoch, String account) {
    owner.coordinator.requireCurrent(epoch);
    if (!owner.hasLocalAccount || owner.account != account) {
      throw SessionChanged();
    }
  }

  /// A client whose saved session the library still accepts, else null.
  Future<WebpacClient?> restore() async {
    final account = owner.account;
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
    if (data['account'] != account || data['session'] is! String) return null;
    final web = client()..session = data['session'] as String;
    try {
      final signedIn = await web.page();
      _guard(epoch, account);
      if (signedIn) return web;
    } catch (_) {
      web.close();
      rethrow;
    }
    web.close();
    return null;
  }

  /// Signs in to the library with the school password and saves the session.
  Future<WebpacClient> establish(String account, String password) async {
    final normalized = account.trim().toLowerCase();
    final epoch = owner.coordinator.epoch;
    _guard(epoch, normalized);
    final web = client();
    try {
      await owner.coordinator.authenticate(CampusService.library, (_) async {
        final cookie = await web.login(normalized, password);
        _guard(epoch, normalized);
        await owner.vault.write(
          key,
          jsonEncode({'account': normalized, 'session': cookie}),
        );
        _guard(epoch, normalized);
      });
      if (web.session != null) return web;
      // Joined a login already in flight; use the session it saved.
      web.close();
      final restored = await restore();
      if (restored == null) throw StateError('圖書館登入尚未建立');
      return restored;
    } catch (_) {
      web.close();
      rethrow;
    }
  }

  /// Library sign-in failing must never fail the school login itself.
  static Future<void> establishQuietly(
    CampusSession owner,
    String account,
    String password,
  ) async {
    try {
      (await LibrarySpaceSession(owner).establish(account, password)).close();
    } catch (_) {}
  }
}
