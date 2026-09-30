import 'dart:async';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../core/session/campus_session.dart';
import 'remember_school_login.dart';
import 'school_login_capture.dart';
import 'school_login_engine.dart';

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
    SchoolLoginDriver? driver;
    bool closed = false;

    void guard() {
      session.coordinator.requireCurrent(epoch);
      if (closed ||
          session.account != owner ||
          remembered.revision != revision) {
        throw StateError('Session changed');
      }
    }

    Future<void> close() async {
      closed = true;
      driver?.cancel();
      final old = view;
      view = null;
      await old?.dispose();
    }

    session.registerCleanup(close);
    try {
      final credentials = await remembered.restore();
      guard();
      if (credentials == null || credentials.account != owner) return false;
      // Same flow as the login screen: wait for the school's verification to
      // enable 登入, press it once, then accept the verified token.
      final active = driver = SchoolLoginDriver(
        account: credentials.account,
        password: credentials.password,
        deadline: const Duration(seconds: 25),
      );
      view = HeadlessInAppWebView(
        initialUrlRequest: URLRequest(url: WebUri('$schoolLoginUri')),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          sharedCookiesEnabled: true,
          useShouldOverrideUrlLoading: true,
          allowFileAccess: false,
        ),
        shouldOverrideUrlLoading: (_, action) async {
          if (!isSchoolLoginOrigin(Uri.tryParse('${action.request.url}'))) {
            return NavigationActionPolicy.CANCEL;
          }
          return NavigationActionPolicy.ALLOW;
        },
        onWebViewCreated: active.attach,
        onLoadStart: (_, _) => active.pageStarted(),
        onLoadStop: (_, _) => active.tick(),
        onReceivedError: (_, request, _) {
          if (request.isForMainFrame == true) active.cancel();
        },
      );
      await view!.run().timeout(const Duration(seconds: 5));
      final outcome = await active.outcome;
      guard();
      if (outcome is! SchoolLoginSucceeded) return false;
      await session.acceptToken(outcome.token, owner, epoch: epoch);
      guard();
      return true;
    } catch (_) {
      return false;
    } finally {
      try {
        await close();
      } finally {
        driver?.dispose();
        session.unregisterCleanup(close);
      }
    }
  }
}
