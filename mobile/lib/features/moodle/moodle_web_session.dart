import 'dart:async';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../authentication/remember_school_login.dart';
import 'moodle_demo.dart';
import 'moodle_repository.dart';

/// What the hidden WebView does after each finished page load.
enum MoodleWebStep {
  /// A redirect is still on its way.
  wait,

  /// The wanted page is open and signed in.
  done,

  /// Signed in, but Moodle landed elsewhere; open the wanted page again.
  retarget,

  /// The login page: try a one-time auto-login key first.
  useKey,

  /// The key did not work: sign in with the remembered school password.
  submitPassword,

  /// Both ways failed; only the student can sign in now.
  fail,
}

const _host = 'euni.niu.edu.tw';
const _autologin = '/admin/tool/mobile/autologin.php';

/// Pure decision for one page load, kept apart from the WebView for tests.
/// [exact] is for reads that need [target] itself; a plain sign-in accepts
/// any signed-in M 園區 page.
MoodleWebStep moodleWebStep({
  required Uri page,
  required Uri target,
  required bool loginForm,
  required bool signedOut,
  required bool triedKey,
  required bool triedPassword,
  bool exact = true,
}) {
  if (page.host != _host) return MoodleWebStep.wait;
  // A good key redirects away from autologin.php; stopping on it is an error.
  if (page.path == _autologin) {
    return triedPassword ? MoodleWebStep.fail : MoodleWebStep.retarget;
  }
  if (loginForm || signedOut) {
    if (!triedKey) return MoodleWebStep.useKey;
    if (!triedPassword) return MoodleWebStep.submitPassword;
    return MoodleWebStep.fail;
  }
  if (page.path.startsWith('/login/')) return MoodleWebStep.wait;
  if (!exact || page.path == target.path) return MoodleWebStep.done;
  return MoodleWebStep.retarget;
}

/// Signs the shared WebView cookie store into the M 園區 website, which the
/// REST token does not do. Tries the existing cookies, then Moodle's one-time
/// auto-login key (one per six minutes per user), then the remembered school
/// password on the website's own login form, like a student would.
///
/// Read-only: callers pass view pages only, never marking or submit URLs.
class MoodleWebSession {
  MoodleWebSession._();

  static final Uri home = Uri.https(_host, '/my/');
  static const failure = '無法自動登入 M 園區網站，請開啟校方頁面登入一次。';

  /// Hidden sign-ins share one cookie store, so they run one at a time.
  static Future<void> _queue = Future.value();
  static Future<void>? _signingIn;
  static String? _signedInAccount;
  static DateTime? _signedInAt;

  /// Moodle website sessions last hours; skip the check for a while.
  static const _fresh = Duration(minutes: 10);

  static Future<T> _serial<T>(Future<T> Function() task) {
    final next = _queue.then((_) => task());
    _queue = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  static void _remember(MoodleRepository repository) {
    _signedInAccount = repository.session.account.toLowerCase();
    _signedInAt = DateTime.now();
  }

  /// Forget the cached sign-in, e.g. when a page shows the login form anyway.
  static void expire() => _signedInAt = null;

  /// Makes sure the website is signed in before a visible page opens.
  static Future<void> ensureSignedIn(
    MoodleRepository repository, {
    bool force = false,
  }) {
    if (repository is DemoMoodleRepository) {
      return Future.error(const FormatException('示範模式不開啟 M 園區網頁'));
    }
    final at = _signedInAt;
    if (!force &&
        at != null &&
        _signedInAccount == repository.session.account.toLowerCase() &&
        DateTime.now().difference(at) < _fresh) {
      return Future.value();
    }
    return _signingIn ??= _serial(
      () => _visit(repository, home, exact: false),
    ).then<void>((_) {}).whenComplete(() => _signingIn = null);
  }

  /// Returns the rendered HTML of [target], signing in on the way if needed.
  static Future<String> load(MoodleRepository repository, Uri target) =>
      _serial(() => _visit(repository, target, exact: true));

  static Future<String> _visit(
    MoodleRepository repository,
    Uri target, {
    required bool exact,
  }) async {
    repository.requireCurrent();
    final result = Completer<String>();
    var triedKey = false, triedPassword = false, retargets = 0;
    HeadlessInAppWebView? view;
    void fail(String message) {
      if (!result.isCompleted) result.completeError(FormatException(message));
    }

    Future<void> open(InAppWebViewController web, Uri uri) =>
        web.loadUrl(urlRequest: URLRequest(url: WebUri('$uri')));

    Future<void> submitPassword(InAppWebViewController web, Uri page) async {
      triedPassword = true;
      final owner = repository.owner;
      final saved = owner == null
          ? null
          : await RememberSchoolLogin.forSession(owner).restore();
      repository.requireCurrent();
      if (saved == null ||
          saved.account.toLowerCase() !=
              repository.session.account.toLowerCase()) {
        return fail(failure);
      }
      if (page.path != '/login/index.php') {
        // Signed out on another page: go to the form; Moodle returns here.
        return open(web, Uri.https(_host, '/login/index.php'));
      }
      final sent = await web.callAsyncJavaScript(
        functionBody: '''
          const form = document.getElementById('login');
          const user = form && form.querySelector('input[name="username"]');
          const pass = form && form.querySelector('input[name="password"]');
          if (!user || !pass) return false;
          user.value = account;
          pass.value = password;
          setTimeout(() => form.submit(), 0);
          return true;
        ''',
        arguments: {'account': saved.account, 'password': saved.password},
      );
      if (sent?.value != true) fail(failure);
    }

    Future<void> useKey(InAppWebViewController web, Uri page) async {
      triedKey = true;
      Uri? entry;
      try {
        final uri = await repository.webUri(target);
        if (uri.path == _autologin) entry = uri;
      } catch (_) {
        // Rate limited or no private token: fall through to the password.
      }
      repository.requireCurrent();
      if (entry != null) return open(web, entry);
      return submitPassword(web, page);
    }

    view = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(url: WebUri('$target')),
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
        final page = Uri.parse('$url');
        try {
          final state = page.host == _host
              ? await web.evaluateJavascript(
                  source: '''
                    [!!document.querySelector('#login input[name="password"], #page-login-index'),
                     document.body.classList.contains('notloggedin')]
                  ''',
                )
              : null;
          final step = moodleWebStep(
            page: page,
            target: target,
            loginForm: state is List && state.first == true,
            signedOut: state is List && state.last == true,
            triedKey: triedKey,
            triedPassword: triedPassword,
            exact: exact,
          );
          switch (step) {
            case MoodleWebStep.wait:
              return;
            case MoodleWebStep.done:
              final html = await web.evaluateJavascript(
                source: 'document.documentElement.outerHTML',
              );
              if (html is String && html.isNotEmpty) {
                _remember(repository);
                result.complete(html);
              } else {
                fail('M 園區網頁沒有內容');
              }
            case MoodleWebStep.retarget:
              if (++retargets > 2) return fail(failure);
              await open(web, target);
            case MoodleWebStep.useKey:
              await useKey(web, page);
            case MoodleWebStep.submitPassword:
              await submitPassword(web, page);
            case MoodleWebStep.fail:
              fail(failure);
          }
        } catch (error) {
          if (!result.isCompleted) result.completeError(error);
        }
      },
      onReceivedError: (_, request, error) {
        if (request.isForMainFrame == true) fail('無法連上 M 園區網站');
      },
    );
    try {
      await view.run().timeout(const Duration(seconds: 5));
      final html = await result.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw const FormatException('M 園區網站回應逾時'),
      );
      repository.requireCurrent();
      return html;
    } catch (_) {
      expire();
      rethrow;
    } finally {
      unawaited(view.dispose().catchError((Object _) {}));
    }
  }

  static bool _allowed(Uri u) =>
      u.scheme == 'https' &&
      u.userInfo.isEmpty &&
      const {
        'euni.niu.edu.tw',
        'sso.niu.edu.tw',
        'ccsys.niu.edu.tw',
        'ccsys1.niu.edu.tw',
      }.contains(u.host);
}
