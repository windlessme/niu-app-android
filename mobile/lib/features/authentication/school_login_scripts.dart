// Page scripts and outcomes for the school SSO sign-in, kept free of
// Flutter imports so DOM fixtures can run them under plain Dart.
import 'dart:convert';

/// Result of one automated sign-in on the school SSO page (as on iOS).
sealed class SchoolLoginOutcome {
  const SchoolLoginOutcome();
}

class SchoolLoginSucceeded extends SchoolLoginOutcome {
  const SchoolLoginSucceeded(this.token);
  final String token;
}

class SchoolLoginRejected extends SchoolLoginOutcome {
  const SchoolLoginRejected(this.kind, this.title, this.message);
  final SchoolLoginRejection kind;
  final String title, message;
}

enum SchoolLoginRejection {
  credentials,
  passwordExpired,
  accountLocked,
  timeout,
  unavailable,
  other,
}

/// Maps the school's visible error popup to a rejection (iOS rules).
SchoolLoginRejected classifySchoolLoginError(String message) {
  if (message.contains('鎖定')) {
    return SchoolLoginRejected(
      SchoolLoginRejection.accountLocked,
      '帳號已鎖定',
      message,
    );
  }
  if (message.contains('密碼') && ['到期', '過期', '變更預設密碼'].any(message.contains)) {
    return SchoolLoginRejected(
      SchoolLoginRejection.passwordExpired,
      '密碼已到期',
      message,
    );
  }
  if (message.contains('帳號') || message.contains('密碼')) {
    return SchoolLoginRejected(
      SchoolLoginRejection.credentials,
      '登入失敗',
      message,
    );
  }
  return SchoolLoginRejected(SchoolLoginRejection.other, '登入失敗', message);
}

/// Fills the school's own fields and presses its 登入 button once the page
/// enables it (the button stays disabled until Turnstile issues a token).
/// Never touches the challenge itself. Mirrors iOS `fillModernLoginForm`.
String schoolLoginFillScript(
  String account,
  String password, {
  bool fill = true,
}) =>
    '''
(() => {
  if (window !== window.top || location.origin !== 'https://ccsys1.niu.edu.tw' ||
      location.pathname !== '/SSO/login') return 'blocked';
  const [account, password] = ${jsonEncode([account, password]).replaceAll('<', r'<').replaceAll(' ', r' ').replaceAll(' ', r' ')};
  const usernameField = document.querySelector('#username');
  const passwordField = document.querySelector('#password');
  const form = document.querySelector('form.login-form');
  const submit = document.querySelector('form.login-form button[type="submit"]');
  if (!usernameField || !passwordField || !form || !submit) return 'waiting';
  if (!window.__niuAppSubmitHooked) {
    window.__niuAppSubmitHooked = true;
    form.addEventListener('submit', () => { window.__niuAppSubmitObserved = true; });
  }
  if (window.__niuAppSubmitObserved) return 'submitted';
  if (${fill ? 'true' : 'false'}) {
    const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
    for (const [field, value] of [[usernameField, account], [passwordField, password]]) {
      if (field.value === value) continue;
      setter.call(field, value);
      field.dispatchEvent(new Event('input', { bubbles: true }));
      field.dispatchEvent(new Event('change', { bubbles: true }));
    }
  }
  if (!usernameField.checkValidity() || !passwordField.checkValidity()) return 'invalid_credentials';
  if (submit.disabled) return 'waiting_verification';
  submit.click();
  return 'submitted';
})()
''';

/// Token or a visible error/warning popup. Mirrors iOS `checkModernLoginState`.
const schoolLoginStateScript = r'''
(() => {
  const token = sessionStorage.getItem('niu_sso_token') || '';
  const visible = el => el && el.getClientRects().length > 0
    && getComputedStyle(el).visibility !== 'hidden';
  const popup = document.querySelector('.swal2-popup.swal2-show');
  const popupText = popup ? popup.innerText.trim() : '';
  const warning = popup && (popup.querySelector('.swal2-icon.swal2-warning')
    || popup.getAttribute('data-icon') === 'warning');
  const accountActionRequired = warning && (
    popupText.includes('鎖定') || (popupText.includes('密碼')
      && ['到期', '過期', '變更預設密碼'].some(word => popupText.includes(word))
      && !popupText.includes('即將'))
  );
  const rejected = visible(popup) && (
    popup.querySelector('.swal2-icon.swal2-error')
    || popup.getAttribute('data-icon') === 'error' || accountActionRequired
  );
  const danger = Array.from(document.querySelectorAll('.alert-danger')).find(visible);
  const alert = rejected ? popup : danger;
  return JSON.stringify({ token: token, error: alert ? alert.innerText.trim() : '' });
})()
''';
