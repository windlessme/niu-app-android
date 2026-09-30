import 'dart:async';
import 'dart:convert';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'school_login_capture.dart';
import 'school_login_scripts.dart';

export 'school_login_scripts.dart';

final schoolLoginUri = Uri.parse('https://ccsys1.niu.edu.tw/SSO/login');

/// Polls one school login page every 500 ms until a token or a rejection.
/// Works with both visible and headless WebViews.
class SchoolLoginDriver {
  SchoolLoginDriver({
    required this.account,
    required this.password,
    this.deadline = const Duration(seconds: 120),
  });
  final String account;
  final String password;
  final Duration deadline;
  final _result = Completer<SchoolLoginOutcome>();
  final _clock = Stopwatch();
  InAppWebViewController? _web;
  Timer? _timer;
  bool _busy = false, _filled = false, _submitted = false;

  Future<SchoolLoginOutcome> get outcome => _result.future;
  bool get finished => _result.isCompleted;

  void attach(InAppWebViewController web) {
    _web = web;
    _clock.start();
    _timer ??= Timer.periodic(const Duration(milliseconds: 500), (_) => tick());
  }

  /// A new page load (redirect, retry) fills the form again.
  void pageStarted() {
    _filled = false;
    _submitted = false;
  }

  void finish(SchoolLoginOutcome value) {
    _timer?.cancel();
    if (!_result.isCompleted) _result.complete(value);
  }

  void cancel() => finish(
    const SchoolLoginRejected(SchoolLoginRejection.other, '已取消', '已取消登入'),
  );

  Future<void> tick() async {
    final web = _web;
    if (web == null || _busy || finished) return;
    _busy = true;
    try {
      final url = Uri.tryParse('${await web.getUrl()}');
      if (!isSchoolLoginOrigin(url)) return;
      final raw = await web.evaluateJavascript(source: schoolLoginStateScript);
      if (raw is String) {
        final state = jsonDecode(raw) as Map;
        final token = '${state['token'] ?? ''}';
        final error = '${state['error'] ?? ''}';
        if (token.isNotEmpty) return finish(SchoolLoginSucceeded(token));
        // Human-verification notices are not a rejected password.
        if (error.isNotEmpty &&
            !error.contains('驗證') &&
            !error.toLowerCase().contains('turnstile')) {
          return finish(classifySchoolLoginError(error));
        }
      }
      if (_clock.elapsed >= deadline) {
        return finish(
          const SchoolLoginRejected(
            SchoolLoginRejection.timeout,
            '登入逾時',
            '請完成校方登入頁的人機驗證，再重新登入。',
          ),
        );
      }
      if (_submitted || !isSchoolLoginPage(url)) return;
      final status = await web.evaluateJavascript(
        source: schoolLoginFillScript(account, password, fill: !_filled),
      );
      if (status == 'waiting_verification' || status == 'submitted') {
        _filled = true;
      }
      if (status == 'submitted') _submitted = true;
      if (status == 'invalid_credentials') {
        finish(
          const SchoolLoginRejected(
            SchoolLoginRejection.credentials,
            '登入失敗',
            '學號或密碼格式不正確。',
          ),
        );
      }
    } catch (_) {
      // Navigation can briefly destroy the JavaScript context; retry.
    } finally {
      _busy = false;
    }
  }

  void dispose() => _timer?.cancel();
}
