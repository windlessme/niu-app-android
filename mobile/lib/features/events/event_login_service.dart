import 'dart:async';
import 'dart:convert';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../../core/session/campus_session.dart';
import '../../core/session/session_coordinator.dart';
import '../../core/web/event_cookie_store.dart';

final eventListUri = Uri.https('ccsys.niu.edu.tw', '/MvcTeam/Act');
final eventVerificationUri = Uri.https(
  'ccsys.niu.edu.tw',
  '/MvcTeam/Act/ApplyMe',
);
final eventLoginUri = Uri.https('ccsys.niu.edu.tw', '/MvcTeam/Account/Login', {
  'ReturnUrl': '/MvcTeam/Act/ApplyMe',
});

bool isEventUri(Uri uri) =>
    uri.scheme == 'https' &&
    uri.host == 'ccsys.niu.edu.tw' &&
    uri.port == 443 &&
    uri.userInfo.isEmpty &&
    uri.path.toLowerCase().startsWith('/mvcteam/');

/// Uses the real form and shared browser cookie/redirect machinery. Passwords
/// exist only in this bounded handoff and are never persisted or logged.
class EventLoginService {
  static final _pending = Expando<Future<bool>>();

  Future<void> restore(CampusSession session, int epoch) async {
    session.coordinator.requireCurrent(epoch);
    if (!session.hasLocalAccount) throw SessionChanged();
    await EventCookieStore.restore(session, epoch);
    session.coordinator.requireCurrent(epoch);
    if (!session.hasLocalAccount) throw SessionChanged();
  }

  /// Call after acceptToken verifies this account at this epoch. False means
  /// event reconnect is needed, not that the school SSO login failed.
  Future<bool> establish(
    String account,
    String password,
    CampusSession session,
    int epoch,
  ) async {
    session.coordinator.requireCurrent(epoch);
    if (!session.hasLocalAccount ||
        !session.isSignedIn ||
        session.account != account.trim().toLowerCase()) {
      throw SessionChanged();
    }
    if (password.isEmpty) return false;
    final previous = _pending[session];
    if (previous != null) return previous;
    final task = _establish(account, password, session, epoch);
    _pending[session] = task;
    try {
      return await task;
    } finally {
      if (identical(_pending[session], task)) _pending[session] = null;
    }
  }

  Future<bool> _establish(
    String account,
    String password,
    CampusSession session,
    int epoch,
  ) async {
    final result = Completer<bool>();
    HeadlessInAppWebView? headless;
    bool submitted = false;
    bool closed = false;
    Future<void>? disposing;
    void finish(bool success) {
      if (!result.isCompleted) result.complete(success);
    }

    Future<void> close() => disposing ??= () async {
      closed = true;
      password = '';
      finish(false);
      await headless?.dispose().timeout(const Duration(seconds: 3));
    }();
    session.registerCleanup(close);
    final deadline = Timer(const Duration(seconds: 20), () => finish(false));
    try {
      await restore(session, epoch);
      session.coordinator.requireCurrent(epoch);
      if (result.isCompleted || closed) return false;
      headless = HeadlessInAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(eventLoginUri.toString())),
        initialSettings: InAppWebViewSettings(
          incognito: false,
          sharedCookiesEnabled: true,
          javaScriptEnabled: true,
          useShouldOverrideUrlLoading: true,
          allowFileAccess: false,
          allowContentAccess: false,
          supportMultipleWindows: false,
        ),
        shouldOverrideUrlLoading: (_, action) async {
          final uri = Uri.tryParse(action.request.url?.toString() ?? '');
          if (closed || uri == null || !isEventUri(uri)) {
            finish(false);
            return NavigationActionPolicy.CANCEL;
          }
          return NavigationActionPolicy.ALLOW;
        },
        onLoadStop: (web, url) async {
          if (closed || result.isCompleted || url == null) return;
          try {
            session.coordinator.requireCurrent(epoch);
            final uri = Uri.parse(url.toString());
            if (!isEventUri(uri)) return finish(false);
            if (uri.path.toLowerCase() == '/mvcteam/account/login') {
              if (submitted) return finish(false);
              if (!session.hasLocalAccount ||
                  !session.isSignedIn ||
                  session.account != account.trim().toLowerCase()) {
                return finish(false);
              }
              submitted = true;
              final script = eventLoginFormScript(account, password);
              password = '';
              final value = await web.evaluateJavascript(source: script);
              if (value != 'submitted') finish(false);
              return;
            }
            // Act is public. Verify the protected ApplyMe response instead.
            if (uri.path.toLowerCase() != '/mvcteam/act/applyme') {
              await web.loadUrl(
                urlRequest: URLRequest(
                  url: WebUri(eventVerificationUri.toString()),
                ),
              );
              return;
            }
            final verified = await web.evaluateJavascript(
              source: eventSessionVerifiedScript,
            );
            session.coordinator.requireCurrent(epoch);
            if (verified != true || closed || result.isCompleted) {
              return finish(false);
            }
            await EventCookieStore.save(session, epoch);
            session.coordinator.requireCurrent(epoch);
            finish(true);
          } catch (_) {
            finish(false);
          }
        },
        onReceivedError: (_, request, error) {
          if (request.isForMainFrame == true) finish(false);
        },
        onReceivedHttpError: (_, request, response) {
          if (request.isForMainFrame == true) finish(false);
        },
      );
      await headless.run().timeout(const Duration(seconds: 5));
      final success = await result.future;
      session.coordinator.requireCurrent(epoch);
      return success;
    } on SessionChanged {
      rethrow;
    } catch (_) {
      return false;
    } finally {
      deadline.cancel();
      try {
        await close();
      } finally {
        session.unregisterCleanup(close);
      }
    }
  }
}

const eventSessionVerifiedScript = r'''
(() => {
  const url = new URL(location.href);
  return url.origin === 'https://ccsys.niu.edu.tw' &&
    url.pathname.toLowerCase() === '/mvcteam/act/applyme' &&
    document.readyState === 'complete' &&
    !document.querySelector('input[type="password"], #loginLink') &&
    !!document.querySelector('.container.body-content') &&
    !!(document.body?.innerText || '').trim();
})()
''';

String eventLoginFormScript(String account, String password) =>
    '''
(() => {
  const url = new URL(location.href);
  if (url.origin !== 'https://ccsys.niu.edu.tw' ||
      url.pathname.toLowerCase() !== '/mvcteam/account/login') return 'wrong-page';
  const form = document.querySelector('#loginForm form');
  if (!form || form.method.toLowerCase() !== 'post') return 'missing-form';
  const action = new URL(form.action, location.href);
  if (action.origin !== url.origin || action.pathname.toLowerCase() !== '/mvcteam/account/login') return 'wrong-action';
  const account = form.querySelector('input[name="Account"]');
  const password = form.querySelector('input[name="Password"][type="password"]');
  const token = form.querySelector('input[name="__RequestVerificationToken"][type="hidden"]');
  if (!account || !password || !token?.value) return 'missing-fields';
  action.searchParams.set('ReturnUrl', '/MvcTeam/Act/ApplyMe');
  form.action = action.href;
  account.value = ${jsonEncode(account)};
  password.value = ${jsonEncode(password)};
  // Submit only this checked login form, preserving its anti-forgery field.
  HTMLFormElement.prototype.submit.call(form);
  return 'submitted';
})()
''';
