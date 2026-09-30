import 'dart:async';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'moodle_repository.dart';

/// Loads one M 園區 page in a hidden WebView, first signing the shared
/// WebView cookie store into the website with Moodle's one-time auto-login
/// link. Later HTTP reads can then reuse those cookies, which is what a
/// student otherwise achieves by opening the website manually once.
///
/// Read-only: callers pass view pages only, never marking or submit URLs.
class MoodleWebSession {
  MoodleWebSession._();

  static Future<String>? _pending;
  static Uri? _pendingTarget;

  static bool _isLogin(Uri uri) =>
      uri.host != 'euni.niu.edu.tw' ||
      uri.path.startsWith('/login/') ||
      uri.path == '/admin/tool/mobile/autologin.php';

  static bool _allowed(Uri u) =>
      u.scheme == 'https' &&
      u.userInfo.isEmpty &&
      const {
        'euni.niu.edu.tw',
        'sso.niu.edu.tw',
        'ccsys.niu.edu.tw',
        'ccsys1.niu.edu.tw',
      }.contains(u.host);

  /// Returns the rendered HTML of [target] once the website session exists.
  static Future<String> load(MoodleRepository repository, Uri target) {
    // Concurrent readers for the same page share one sign-in.
    if (_pending != null && _pendingTarget == target) return _pending!;
    _pendingTarget = target;
    return _pending = _load(repository, target).whenComplete(() {
      _pending = null;
      _pendingTarget = null;
    });
  }

  static Future<String> _load(MoodleRepository repository, Uri target) async {
    repository.requireCurrent();
    Uri entry;
    try {
      entry = await repository.webUri(target);
    } catch (_) {
      // Auto-login keys are rate limited; existing cookies may still work.
      entry = target;
    }
    repository.requireCurrent();
    final result = Completer<String>();
    HeadlessInAppWebView? view;
    void fail(String message) {
      if (!result.isCompleted) result.completeError(FormatException(message));
    }

    view = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(url: WebUri('$entry')),
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
        final uri = Uri.tryParse('${action.request.url}');
        return uri != null && _allowed(uri)
            ? NavigationActionPolicy.ALLOW
            : NavigationActionPolicy.CANCEL;
      },
      onLoadStop: (web, url) async {
        if (result.isCompleted || url == null) return;
        final uri = Uri.parse('$url');
        if (_isLogin(uri)) {
          // Auto-login redirects through here; a login *form* means it failed.
          final form = await web.evaluateJavascript(
            source:
                "!!document.querySelector('input[name=\"password\"],#page-login-index')",
          );
          if (form == true) fail('無法自動登入 M 園區網站，請開啟校方紀錄登入一次。');
          return;
        }
        if (uri.path != target.path) return;
        final html = await web.evaluateJavascript(
          source: 'document.documentElement.outerHTML',
        );
        if (html is String && html.isNotEmpty) {
          result.complete(html);
        } else {
          fail('M 園區網頁沒有內容');
        }
      },
      onReceivedError: (_, request, error) {
        if (request.isForMainFrame == true) fail('無法連上 M 園區網站');
      },
    );
    try {
      await view.run().timeout(const Duration(seconds: 5));
      final html = await result.future.timeout(
        const Duration(seconds: 25),
        onTimeout: () => throw const FormatException('M 園區網站回應逾時'),
      );
      repository.requireCurrent();
      return html;
    } finally {
      unawaited(view.dispose().catchError((Object _) {}));
    }
  }
}
