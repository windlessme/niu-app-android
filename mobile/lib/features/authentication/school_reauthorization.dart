import 'dart:async';
import 'dart:collection';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../core/session/campus_session.dart';
import 'remember_school_login.dart';
import 'school_login_capture.dart';

/// One bounded, read-only authentication recovery per account session.
class SchoolReauthorization {
  static final _pending = Expando<Future<bool>>();

  static Future<bool> restore(CampusSession session) async {
    if (session.isSignedIn) return true;
    if (!session.hasLocalAccount) return false;
    final previous = _pending[session];
    if (previous != null) return previous;
    final task = _restore(session);
    _pending[session] = task;
    try {
      return await task;
    } finally {
      if (identical(_pending[session], task)) _pending[session] = null;
    }
  }

  static Future<bool> _restore(CampusSession session) async {
    final epoch = session.coordinator.epoch;
    final owner = session.account;
    final remembered = RememberSchoolLogin.forSession(session);
    final revision = remembered.revision;
    HeadlessInAppWebView? view;
    Timer? timer;
    Timer? deadline;
    final result = Completer<bool>();
    bool closed = false;
    bool checking = false;
    bool submitted = false;
    void finish(bool value) {
      if (!result.isCompleted) result.complete(value);
    }

    void guard() {
      session.coordinator.requireCurrent(epoch);
      if (closed ||
          result.isCompleted ||
          session.account != owner ||
          remembered.revision != revision) {
        throw StateError('Session changed');
      }
    }

    Future<void> close() async {
      closed = true;
      timer?.cancel();
      deadline?.cancel();
      finish(false);
      final old = view;
      view = null;
      await old?.dispose();
    }

    session.registerCleanup(close);
    try {
      final credentials = await remembered.restore();
      guard();
      if (credentials == null || credentials.account != owner) return false;
      final started = Stopwatch()..start();
      Future<void> check(InAppWebViewController web) async {
        if (checking || closed || result.isCompleted) return;
        checking = true;
        try {
          guard();
          final url = await web.getUrl();
          if (!isSchoolLoginOrigin(Uri.tryParse('$url'))) return;
          final token = await web.evaluateJavascript(
            source: "sessionStorage.getItem('niu_sso_token') || ''",
          );
          guard();
          if (token is String && token.isNotEmpty) {
            await session.acceptToken(token, owner, epoch: epoch);
            guard();
            finish(true);
            return;
          }
          if (submitted || !isSchoolLoginPage(Uri.tryParse('$url'))) return;
          await web.evaluateJavascript(
            source: schoolLoginPrefillScript(credentials),
          );
          guard();
          final status = await web.evaluateJavascript(
            source: schoolAutomaticSubmitScript,
          );
          guard();
          if (status == 'submitted') submitted = true;
          if (status == 'interaction-required' || status == 'blocked') {
            finish(false);
          }
          if (status == 'waiting' &&
              started.elapsed > const Duration(seconds: 8)) {
            finish(false);
          }
        } catch (_) {
          finish(false);
        } finally {
          checking = false;
        }
      }

      deadline = Timer(const Duration(seconds: 20), () => finish(false));
      view = HeadlessInAppWebView(
        initialUrlRequest: URLRequest(
          url: WebUri('https://ccsys1.niu.edu.tw/SSO/login'),
        ),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          sharedCookiesEnabled: true,
          useShouldOverrideUrlLoading: true,
          allowFileAccess: false,
        ),
        initialUserScripts: UnmodifiableListView([
          UserScript(
            source: schoolLoginCaptureScript('automatic-recovery'),
            injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
          ),
        ]),
        shouldOverrideUrlLoading: (_, action) async {
          if (!isSchoolLoginOrigin(Uri.tryParse('${action.request.url}'))) {
            finish(false);
            return NavigationActionPolicy.CANCEL;
          }
          return NavigationActionPolicy.ALLOW;
        },
        onWebViewCreated: (web) {
          timer = Timer.periodic(
            const Duration(milliseconds: 500),
            (_) => check(web),
          );
        },
        onLoadStop: (web, _) => check(web),
        onReceivedError: (_, request, _) {
          if (request.isForMainFrame == true) finish(false);
        },
        onReceivedHttpError: (_, request, _) {
          if (request.isForMainFrame == true) finish(false);
        },
      );
      await view!.run().timeout(const Duration(seconds: 5));
      return await result.future;
    } catch (_) {
      return false;
    } finally {
      try {
        await close();
      } finally {
        session.unregisterCleanup(close);
      }
    }
  }
}

/// Click only the school's Angular login button. Never solve or alter CAPTCHA.
const schoolAutomaticSubmitScript = r'''
(() => {
  if (window !== window.top || location.origin !== 'https://ccsys1.niu.edu.tw' || location.pathname !== '/SSO/login') return 'blocked';
  if (window.__niuAutomaticSubmitted) return 'submitted';
  const form = document.querySelector('form.login-form');
  if (!form) return 'waiting';
  if (form.querySelector('app-turnstile-widget, .cf-turnstile, .g-recaptcha, .h-captcha, iframe[src*="challenges.cloudflare.com"], iframe[src*="recaptcha"], input[name*="captcha" i], input[name*="otp" i]')) return 'interaction-required';
  const account = form.querySelector('input#username');
  const password = form.querySelector('input#password');
  const button = form.querySelector('button.btn-login[type="submit"],button.btn-login[type="button"]');
  if (!account?.value || !password?.value || !button || button.disabled) return 'waiting';
  window.__niuAutomaticSubmitted = true;
  button.click();
  return 'submitted';
})()
''';
