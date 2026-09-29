import 'dart:convert';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../session/campus_session.dart';

/// Account-bound secure storage supplements WebView's persistent cookie store:
/// ASP.NET authentication cookies may be session-only on Android.
class EventCookieStore {
  static final _restored = Expando<int>();
  static final _url = WebUri('https://ccsys.niu.edu.tw/MvcTeam/Act');
  static const _timeout = Duration(seconds: 3);

  static Future<void> restore(CampusSession session, int epoch) async {
    session.coordinator.requireCurrent(epoch);
    if (_restored[session] == epoch) return;
    Future<void>? work;
    Future<void> cleanup() async => await work;
    session.registerCleanup(cleanup);
    work = () async {
      final elapsed = Stopwatch()..start();
      final raw = await session.vault.read('eventSession').timeout(_timeout);
      session.coordinator.requireCurrent(epoch);
      if (raw == null || raw.isEmpty) return;
      final saved = jsonDecode(raw) as Map<String, dynamic>;
      if (saved['account'] != session.account) return;
      final manager = CookieManager.instance();
      final existing = await manager.getCookies(url: _url).timeout(_timeout);
      session.coordinator.requireCurrent(epoch);
      for (final value in (saved['cookies'] as List).take(30)) {
        if (elapsed.elapsed >= const Duration(seconds: 6)) break;
        final cookie = Cookie.fromMap(Map<String, dynamic>.from(value as Map))!;
        if (!usableEventCookie(cookie) ||
            existing.any((current) => current.name == cookie.name)) {
          continue;
        }
        session.coordinator.requireCurrent(epoch);
        await manager
            .setCookie(
              url: _url,
              name: cookie.name,
              value: cookie.value.toString(),
              domain: cookie.domain,
              path: cookie.path ?? '/MvcTeam',
              expiresDate: cookie.expiresDate,
              isSecure: cookie.isSecure ?? true,
              isHttpOnly: cookie.isHttpOnly ?? true,
              sameSite: cookie.sameSite,
            )
            .timeout(_timeout);
      }
      session.coordinator.requireCurrent(epoch);
    }();
    try {
      await work;
      session.coordinator.requireCurrent(epoch);
      _restored[session] = epoch;
    } catch (_) {
      // Still allow the retained browser cookie session, or show reconnect.
      session.coordinator.requireCurrent(epoch);
    } finally {
      session.unregisterCleanup(cleanup);
    }
  }

  static Future<void> save(CampusSession session, int epoch) async {
    Future<void>? work;
    Future<void> cleanup() async => await work;
    session.registerCleanup(cleanup);
    work = () async {
      session.coordinator.requireCurrent(epoch);
      final cookies = await CookieManager.instance()
          .getCookies(url: _url)
          .timeout(_timeout);
      session.coordinator.requireCurrent(epoch);
      await session.vault
          .write(
            'eventSession',
            jsonEncode({
              'account': session.account,
              'cookies': cookies
                  .where(usableEventCookie)
                  .map((c) => c.toMap())
                  .toList(),
            }),
          )
          .timeout(_timeout);
      session.coordinator.requireCurrent(epoch);
      _restored[session] = epoch;
    }();
    try {
      await work;
    } finally {
      session.unregisterCleanup(cleanup);
    }
  }
}

bool usableEventCookie(Cookie cookie) {
  final domain = cookie.domain?.replaceFirst(RegExp(r'^\.'), '').toLowerCase();
  final path = cookie.path;
  return (domain == null || domain == 'ccsys.niu.edu.tw') &&
      (path == null ||
          path == '/' ||
          path == '/MvcTeam' ||
          path == '/MvcTeam/') &&
      cookie.name.isNotEmpty &&
      cookie.value is String &&
      (cookie.expiresDate == null ||
          cookie.expiresDate! > DateTime.now().millisecondsSinceEpoch);
}
