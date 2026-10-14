import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../authentication/school_login_capture.dart';
import 'moodle_login_captcha.dart';

/// The page a question activity loads in; a seam for tests.
abstract interface class QuestionLoginPage {
  Future<void> load(Uri url);

  /// Runs [body] as an async function with [arguments] as its parameters.
  Future<Object?> run(String body, Map<String, Object?> arguments);
}

class WebQuestionLoginPage implements QuestionLoginPage {
  WebQuestionLoginPage(this.web);
  final InAppWebViewController web;
  @override
  Future<void> load(Uri url) =>
      web.loadUrl(urlRequest: URLRequest(url: WebUri('$url')));
  @override
  Future<Object?> run(String body, Map<String, Object?> arguments) async =>
      (await web.callAsyncJavaScript(
        functionBody: body,
        arguments: arguments,
      ))?.value;
}

/// How far an activity has gone through automatic M 園區 login recovery.
enum QuestionLoginStep {
  direct,
  autologin,
  schoolSso,
  formLogin,
  accountRefresh,
  refreshedSso,
  manual,
  done,
}

/// Recovers M 園區's website login for question activities, as on iOS:
/// each automatic route runs once, in order — the app's auto-login key, the
/// school's SSO handoff, the saved account on M 園區's own login form (with
/// its five-digit code read on the device), then a fresh school sign-in and
/// SSO again. Only when all fail does the school's login page show. A login
/// that ends on M 園區's home page still opens the activity once.
class QuestionLoginRecovery {
  QuestionLoginRecovery({
    required this.target,
    required this.autologin,
    required this.credentials,
    required this.reauthorize,
    required this.onManual,
    required this.onTimeout,
    this.readCaptcha = readMoodleCaptcha,
    this.timeout = const Duration(seconds: 25),
  });

  final Uri target;

  /// Moodle's one-time login link for [target]; the target itself when the
  /// app has no key.
  final Future<Uri> Function() autologin;

  /// The remembered school account, if the student chose to keep it.
  final Future<SubmittedSchoolCredentials?> Function() credentials;

  /// Signs in to the school again in the background.
  final Future<bool> Function() reauthorize;
  final void Function() onManual;
  final void Function(String message) onTimeout;
  final Future<String?> Function(Uint8List png) readCaptcha;
  final Duration timeout;

  static final std002 = Uri.parse('https://ccsys.niu.edu.tw/SSO/Std002.aspx');
  static final moodleLogin = Uri.parse(
    'https://euni.niu.edu.tw/login/index.php',
  );

  /// The SSO link into M 園區 found on Std002 this app run.
  static Uri? euniLink;

  static const maxFormAttempts = 3;

  QuestionLoginPage? page;
  QuestionLoginStep step = QuestionLoginStep.direct;

  /// A handoff is under way: the next M 園區 page that isn't an activity
  /// should open the target.
  bool handoff = false;
  bool _refreshed = false;
  int _formAttempts = 0;
  int _generation = 0;
  Timer? _timer;

  /// Recovery owns the page; question snapshots should wait.
  bool get busy =>
      step != QuestionLoginStep.done && step != QuestionLoginStep.manual;

  /// A fresh load of the activity; [viaKey] when it went through auto-login.
  void start({required bool viaKey}) {
    _generation++;
    step = viaKey ? QuestionLoginStep.autologin : QuestionLoginStep.direct;
    handoff = false;
    _refreshed = false;
    _formAttempts = 0;
    _arm();
  }

  void dispose() {
    _generation++;
    _timer?.cancel();
  }

  static bool isMoodleLogin(Uri url) =>
      url.host == 'euni.niu.edu.tw' && url.path.startsWith('/login/');

  /// Same rules as iOS's SSOGUIDBridge.isSessionExpiredURL.
  static bool isSchoolSessionExpired(Uri url) {
    final host = url.host.toLowerCase();
    if (!const {
      'acade.niu.edu.tw',
      'ccsys.niu.edu.tw',
      'ccsys1.niu.edu.tw',
    }.contains(host)) {
      return false;
    }
    final path = url.path.toLowerCase();
    if (path == '/sso/login' && host != 'acade.niu.edu.tw') return true;
    if (host == 'ccsys1.niu.edu.tw' &&
        (path == '/sso' || path.startsWith('/sso/'))) {
      return true;
    }
    final guid = url.queryParameters.entries.any(
      (e) => e.key.toLowerCase() == 'guid' && e.value.isNotEmpty,
    );
    return host == 'acade.niu.edu.tw' && path == '/niu/logout.aspx' ||
        path.endsWith('/timeoutpage.aspx') ||
        path.endsWith('/default.aspx') ||
        path.endsWith('/login.aspx') && !guid ||
        path.endsWith('/account/login');
  }

  void _arm([Duration? limit]) {
    _timer?.cancel();
    final generation = _generation;
    _timer = Timer(limit ?? timeout, () {
      if (generation != _generation || !busy) return;
      step = QuestionLoginStep.done;
      onTimeout('問答載入逾時，請檢查網路後重試。');
    });
  }

  bool _stale(int generation) => generation != _generation;

  /// Call on every finished main-frame load.
  Future<void> pageLoaded(Uri url) async {
    final generation = _generation;
    if (isMoodleLogin(url)) {
      if (step == QuestionLoginStep.manual) {
        handoff = true;
        return;
      }
      if (step == QuestionLoginStep.formLogin) {
        // The form was sent and M 園區 asked again: code or password refused.
        await _formLogin(generation);
      } else {
        await _advance(generation);
      }
      return;
    }
    if (url.host == 'ccsys.niu.edu.tw' &&
        url.path.toLowerCase() == '/sso/std002.aspx' &&
        _inSso) {
      await _followStd002(generation);
      return;
    }
    if (isSchoolSessionExpired(url) && _inSso) {
      if (url.path.toLowerCase().contains('logout')) euniLink = null;
      await _advance(generation);
      return;
    }
    if (url.host != 'euni.niu.edu.tw') return;
    if (handoff && !url.path.startsWith('/mod/')) {
      // Home after a login or SSO; open the activity itself, once.
      handoff = false;
      _arm();
      await page?.load(target);
      return;
    }
    if (url.path.startsWith('/mod/') || !busy) {
      handoff = false;
      step = QuestionLoginStep.done;
      _timer?.cancel();
    }
  }

  bool get _inSso =>
      step == QuestionLoginStep.schoolSso ||
      step == QuestionLoginStep.refreshedSso;

  /// The next route after the current one ended on a login page.
  Future<void> _advance(int generation) async {
    switch (step) {
      case QuestionLoginStep.direct:
        step = QuestionLoginStep.autologin;
        _arm();
        Uri next;
        try {
          next = await autologin();
        } catch (_) {
          next = target;
        }
        if (_stale(generation)) return;
        if (next == target) return _sso(QuestionLoginStep.schoolSso);
        await page?.load(next);
      case QuestionLoginStep.autologin:
        await _sso(QuestionLoginStep.schoolSso);
      case QuestionLoginStep.schoolSso:
        step = QuestionLoginStep.formLogin;
        _formAttempts = 0;
        _arm(const Duration(seconds: 60));
        handoff = true;
        await page?.load(moodleLogin);
      case QuestionLoginStep.formLogin:
        await _formLogin(generation);
      case QuestionLoginStep.accountRefresh ||
          QuestionLoginStep.refreshedSso ||
          QuestionLoginStep.manual ||
          QuestionLoginStep.done:
        _manual();
    }
  }

  Future<void> _sso(QuestionLoginStep next) async {
    step = next;
    handoff = true;
    _arm();
    await page?.load(euniLink ?? std002);
  }

  /// Opens M 園區 from the school portal's link list.
  Future<void> _followStd002(int generation) async {
    for (var i = 0; i < 8; i++) {
      final found = await page?.run(_findEuniLink, const {});
      if (_stale(generation)) return;
      if (found is String && found.isNotEmpty) {
        final link = Uri.parse(
          'https://ccsys.niu.edu.tw/SSO/',
        ).resolve(found.trim());
        final lower = '$link'.toLowerCase();
        if (link.scheme == 'https' &&
            !lower.contains('logout.aspx') &&
            const {
              'ccsys.niu.edu.tw',
              'ccsys1.niu.edu.tw',
              'euni.niu.edu.tw',
            }.contains(link.host)) {
          euniLink = link;
          await page?.load(link);
          return;
        }
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 350));
      if (_stale(generation)) return;
    }
    await _advance(generation);
  }

  /// One saved-account attempt on M 園區's login page; after
  /// [maxFormAttempts] it moves on to a fresh school sign-in.
  Future<void> _formLogin(int generation) async {
    final saved = await credentials();
    if (_stale(generation)) return;
    if (saved == null || _formAttempts >= maxFormAttempts) {
      return _gaveUp(generation);
    }
    _formAttempts++;
    String? image;
    for (var i = 0; i < 20 && image == null; i++) {
      final shot = await page?.run(_captureCaptcha, const {});
      if (_stale(generation)) return;
      if (shot is String && shot.startsWith('data:image/png;base64,')) {
        image = shot;
      } else if (shot == 'none') {
        break;
      } else {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    }
    String? code;
    if (image != null) {
      try {
        code = await readCaptcha(
          base64Decode(image.substring(image.indexOf(',') + 1)),
        );
      } catch (_) {
        code = null;
      }
      if (_stale(generation)) return;
      if (code == null) {
        // Unsure of this code; a fresh page brings a new one.
        await page?.load(moodleLogin);
        return;
      }
    } else if (_formAttempts > 1) {
      return _gaveUp(generation);
    }
    final sent = await page?.run(_submit, {
      'username': saved.account,
      'password': saved.password,
      'captcha': code,
      'image': image,
    });
    if (_stale(generation)) return;
    if (sent != 'sent') await page?.load(moodleLogin);
  }

  Future<void> _gaveUp(int generation) async {
    if (_refreshed) return _manual();
    _refreshed = true;
    step = QuestionLoginStep.accountRefresh;
    _timer?.cancel();
    final ok = await reauthorize();
    if (_stale(generation)) return;
    if (!ok) return _manual();
    // The old SSO link belonged to the expired school session.
    euniLink = null;
    await _sso(QuestionLoginStep.refreshedSso);
  }

  void _manual() {
    step = QuestionLoginStep.manual;
    handoff = true;
    _timer?.cancel();
    onManual();
  }
}

/// The M 園區 link on the school portal's Std002 page, or ''.
const _findEuniLink = r'''
const keyword = (href, text) => {
  const h = href.toLowerCase();
  return h.includes('euni') || h.includes('jumpto') ||
    text.includes('M園區') || text.includes('Moodle') || text.includes('數位學習');
};
const ids = [];
for (let i = 12; i >= 0; i--) ids.push(`ctl00_ContentPlaceHolder1_RadListView1_ctrl${i}_HyperLink1`);
const links = [
  ...ids.map((id) => document.getElementById(id)).filter(Boolean),
  ...document.querySelectorAll('a[href]'),
];
for (const link of links) {
  const href = link.getAttribute('href') || '';
  const text = (link.textContent || '').trim();
  if (href && keyword(href, text)) return href;
}
return '';
''';

/// The login code as a PNG data URL, 'none' without a code, or '' while it
/// is still loading.
const _captureCaptcha = r'''
if (location.hostname !== 'euni.niu.edu.tw' || !location.pathname.startsWith('/login/')) return 'none';
const input = document.querySelector('#captcha, input[name="captcha"]');
const image = document.querySelector('#imgcode, img[src*="/auth/posbosscaptcha/captcha.php"]');
if (!input && !image) return document.readyState === 'complete' ? 'none' : '';
if (!image || !image.complete || !image.naturalWidth) return '';
try {
  const canvas = document.createElement('canvas');
  canvas.width = image.naturalWidth;
  canvas.height = image.naturalHeight;
  canvas.getContext('2d').drawImage(image, 0, 0);
  return canvas.toDataURL('image/png');
} catch (e) { return ''; }
''';

/// Fills and sends M 園區's login form, only on that page and only while
/// the code read is still the one shown.
const _submit = r'''
if (location.protocol !== 'https:' || location.hostname !== 'euni.niu.edu.tw' ||
    (location.port && location.port !== '443') ||
    !location.pathname.toLowerCase().startsWith('/login/')) return 'untrusted';
const form = document.querySelector('form#login') ||
  document.querySelector('form[action*="login/index.php"]');
const user = document.querySelector('input[name="username"]#username') ||
  document.querySelector('form#login input[name="username"]');
const pass = document.querySelector('form#login input[name="password"]');
const code = document.querySelector('#captcha, input[name="captcha"]');
if (!form || !user || !pass || (code && !captcha)) return 'missing';
if (code && code.value.trim()) return 'manual';
const current = () => {
  if (!code) return true;
  const img = document.querySelector('#imgcode, img[src*="/auth/posbosscaptcha/captcha.php"]');
  if (!img || !img.complete || !img.naturalWidth) return false;
  const canvas = document.createElement('canvas');
  canvas.width = img.naturalWidth;
  canvas.height = img.naturalHeight;
  canvas.getContext('2d').drawImage(img, 0, 0);
  return canvas.toDataURL('image/png') === image;
};
if (!current()) return 'stale';
const set = (input, value) => {
  input.value = value;
  input.dispatchEvent(new Event('input', { bubbles: true }));
  input.dispatchEvent(new Event('change', { bubbles: true }));
};
set(user, username);
set(pass, password);
if (code) set(code, captcha);
HTMLFormElement.prototype.submit.call(form);
return 'sent';
''';
