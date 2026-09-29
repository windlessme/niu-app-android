import 'dart:convert';

/// Only the top-level school login document receives the per-view capability.
/// No field polling, storage, logging, submission, or CAPTCHA manipulation.
bool isSchoolLoginOrigin(Uri? uri) =>
    uri != null &&
    uri.scheme == 'https' &&
    uri.host == 'ccsys1.niu.edu.tw' &&
    uri.port == 443 &&
    uri.userInfo.isEmpty;

bool isSchoolLoginPage(Uri? uri) =>
    isSchoolLoginOrigin(uri) && uri!.path == '/SSO/login';

/// Returns 'waiting' only while Angular has not created the controls yet.
String schoolLoginPrefillScript(SubmittedSchoolCredentials credentials) =>
    '''
(() => {
  if (window !== window.top || location.origin !== 'https://ccsys1.niu.edu.tw' ||
      location.pathname !== '/SSO/login') return 'blocked';
  if (window.__niuLoginPrefilled || window.__niuLoginEdited) return 'done';
  const account = document.querySelector('form.login-form input#username');
  const password = document.querySelector('form.login-form input#password');
  if (!account || !password) return 'waiting';
  window.__niuLoginPrefilled = true;
  if (account.value || password.value) return 'done';
  const credentials = ${jsonEncode({'account': credentials.account, 'password': credentials.password}).replaceAll('<', r'\u003c').replaceAll('\u2028', r'\u2028').replaceAll('\u2029', r'\u2029')};
  const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
  for (const [input, value] of [[account, credentials.account], [password, credentials.password]]) {
    setter.call(input, value);
    input.dispatchEvent(new Event('input', {bubbles: true}));
    input.dispatchEvent(new Event('change', {bubbles: true}));
  }
  return 'done';
})();
''';

class SubmittedSchoolCredentials {
  const SubmittedSchoolCredentials(this.account, this.password);
  final String account;
  final String password;

  static SubmittedSchoolCredentials? fromMessage(
    Object? message, {
    required Uri? page,
    required String capability,
  }) {
    if (!isSchoolLoginOrigin(page) || message is! Map) return null;
    if (message['capability'] != capability) return null;
    final account = message['account'];
    final password = message['password'];
    if (account is! String ||
        password is! String ||
        account.trim().isEmpty ||
        password.isEmpty ||
        account.length > 256 ||
        password.length > 4096) {
      return null;
    }
    return SubmittedSchoolCredentials(account.trim().toLowerCase(), password);
  }
}

String schoolLoginCaptureScript(String capability) =>
    '''
(() => {
  if (window !== window.top || location.origin !== 'https://ccsys1.niu.edu.tw') return;
  const capability = ${jsonEncode(capability)};
  document.addEventListener('input', event => {
    if (event.isTrusted && event.target instanceof Element &&
        event.target.matches('input#username,input#password')) window.__niuLoginEdited = true;
  }, true);
  function capture(event) {
    if (!event.isTrusted || !/^\\/SSO\\/login\\/?\$/.test(location.pathname)) return;
    const target = event.target;
    if (!(target instanceof Element)) return;
    const form = target.closest('form.login-form');
    if (!form) return;
    const button = form.querySelector('button.btn-login[type="submit"],button.btn-login[type="button"]');
    if (!button || button.disabled) return;
    if (event.type === 'click' && target.closest('button') !== button) return;
    if (event.type === 'keydown' && (event.key !== 'Enter' || event.isComposing || event.repeat ||
        event.ctrlKey || event.altKey || event.metaKey || event.shiftKey ||
        !target.matches('input#username,input#password'))) return;
    if (event.type === 'submit' && target !== form) return;
    // Password visibility toggles its type to text; the ID remains stable.
    const password = form.querySelector('input#password');
    const account = form.querySelector('input#username');
    if (!account?.value || !password?.value) return;
    window.flutter_inappwebview?.callHandler('schoolLoginSubmitted', {
      capability, account: account.value, password: password.value,
      previousToken: sessionStorage.getItem('niu_sso_token') || ''
    });
  }
  // Capture phase runs before Angular's handlers, including click-only variants.
  // Duplicate click/submit messages only replace the transient credentials.
  for (const type of ['submit', 'click', 'keydown']) {
    document.addEventListener(type, capture, true);
  }
})();
''';
