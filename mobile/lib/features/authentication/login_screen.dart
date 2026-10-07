import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../core/analytics/app_analytics.dart';
import '../../core/demo/demo_account.dart';
import '../../core/session/campus_session.dart';
import '../../core/web/portal_policy.dart';
import '../../shared/shared.dart';
import '../events/event_login_service.dart';
import '../library/library_space_session.dart';
import '../mail/mail_session.dart';
import '../moodle/moodle_login_service.dart';
import 'remember_school_login.dart';
import 'school_login_capture.dart';
import 'school_login_engine.dart';
import '../settings/privacy_screen.dart';

/// Native 學號／密碼 form, signing in on the school SSO page like iOS:
/// the page is filled and submitted out of sight, and shown only when the
/// school asks for human verification (after 8 s or on request).
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.session, this.onSignedIn});
  final CampusSession? session;
  final VoidCallback? onSignedIn;
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

enum _Phase { form, signingIn, connecting }

class _LoginScreenState extends State<LoginScreen> {
  late final session = widget.session ?? CampusSession.instance;
  late final epoch = session.coordinator.epoch;
  late final remembered = RememberSchoolLogin.forSession(session);
  final account = TextEditingController();
  final password = TextEditingController();
  final passwordFocus = FocusNode();
  bool obscure = true;
  _Phase phase = _Phase.form;
  bool showPage = false;
  SchoolLoginDriver? driver;
  InAppWebViewController? web;
  Timer? revealTimer;

  /// The school's passwords are at least this long.
  static const minPassword = 8;

  /// A sign-in was tried with a short password: the hint becomes an error.
  bool passwordChecked = false;
  bool get passwordShort =>
      password.text.isNotEmpty && password.text.length < minPassword;
  bool get valid =>
      account.text.trim().isNotEmpty && password.text.length >= minPassword;

  @override
  void initState() {
    super.initState();
    session.registerCleanup(clearWebData);
    remembered.setEnabled(true);
    account.text = session.account ?? '';
    restoreRemembered();
  }

  /// Prefill saved credentials and sign in automatically, as iOS does.
  Future<void> restoreRemembered() async {
    try {
      final saved = await remembered.restore();
      session.coordinator.requireCurrent(epoch);
      if (!mounted || saved == null) return;
      setState(() {
        account.text = saved.account;
        password.text = saved.password;
      });
      if (!session.isSignedIn) unawaited(login());
    } catch (_) {
      // Manual entry remains available.
    }
  }

  Future<void> clearWebData() async {
    driver?.cancel();
    password.clear();
    await web?.stopLoading();
    await web?.evaluateJavascript(
      source: 'sessionStorage.clear(); localStorage.clear();',
    );
  }

  @override
  void dispose() {
    session.unregisterCleanup(clearWebData);
    revealTimer?.cancel();
    driver?.cancel();
    driver?.dispose();
    web?.stopLoading();
    account.dispose();
    password.dispose();
    passwordFocus.dispose();
    super.dispose();
  }

  Future<void> login() async {
    if (phase != _Phase.form) return;
    FocusScope.of(context).unfocus();
    if (passwordShort) {
      setState(() => passwordChecked = true);
      showNiuMessage(context, '密碼至少需要 $minPassword 個字元');
      return;
    }
    if (!valid) {
      showNiuMessage(context, '請輸入學號和密碼');
      return;
    }
    final name = account.text.trim().toLowerCase();
    final secret = password.text;
    if (isDemoLogin(name, secret)) {
      await enterDemo();
      return;
    }
    final active = driver = SchoolLoginDriver(account: name, password: secret);
    setState(() {
      phase = _Phase.signingIn;
      showPage = false;
    });
    revealTimer = Timer(const Duration(seconds: 8), () {
      if (mounted && phase == _Phase.signingIn) setState(() => showPage = true);
    });
    final outcome = await active.outcome;
    revealTimer?.cancel();
    if (!mounted || !identical(driver, active)) return;
    switch (outcome) {
      case SchoolLoginSucceeded(:final token):
        AppAnalytics.instance.event('login', {'method': 'school'});
        await complete(token, name, secret);
      case SchoolLoginRejected():
        await web?.stopLoading();
        setState(() {
          phase = _Phase.form;
          showPage = false;
          web = null;
        });
        if (outcome.kind == SchoolLoginRejection.other &&
            outcome.message == '已取消登入') {
          return;
        }
        AppAnalytics.instance.event('login_failed', {
          'reason': outcome.kind.name,
        });
        if (outcome.kind == SchoolLoginRejection.credentials) {
          // As on iOS: never keep a password the school rejected.
          await remembered.forget();
          remembered.setEnabled(true);
        }
        if (mounted) await showRejection(outcome);
    }
  }

  /// The review account never reaches the school login page.
  Future<void> enterDemo() async {
    setState(() => phase = _Phase.connecting);
    try {
      await session.enterDemo();
    } catch (error) {
      if (!mounted) return;
      setState(() => phase = _Phase.form);
      await showRejection(
        SchoolLoginRejected(
          SchoolLoginRejection.other,
          '無法進入示範模式',
          '$error'.contains('切換帳號') ? '要切換帳號，請先到設定登出。' : '請稍後再試一次。',
        ),
      );
      return;
    }
    if (!mounted) return;
    password.clear();
    HapticFeedback.mediumImpact();
    if (widget.onSignedIn != null) {
      widget.onSignedIn!();
    } else if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> complete(String token, String name, String secret) async {
    // If the student signed in on the visible page, the account comes from
    // the school, not from the form.
    final typed = !showPage;
    try {
      session.coordinator.requireCurrent(epoch);
      final revision = remembered.revision;
      await session.acceptToken(token, typed ? name : null, epoch: epoch);
      session.coordinator.requireCurrent(epoch);
      if (!mounted) return;
      setState(() => phase = _Phase.connecting);
      final verified = session.account;
      if (verified == name) {
        final credentials = SubmittedSchoolCredentials(name, secret);
        try {
          await remembered.saveVerified(
            credentials,
            epoch: epoch,
            consentRevision: revision,
          );
        } catch (_) {}
        // M 園區、活動報名 and the library authenticate separately; failures
        // stay local.
        await Future.wait<void>([
          () async {
            try {
              await MoodleLoginService(
                session,
              ).establish(account: name, password: secret, epoch: epoch);
            } catch (_) {}
          }(),
          () async {
            try {
              await EventLoginService().establish(name, secret, session, epoch);
            } catch (_) {}
          }(),
          LibrarySpaceSession.establishQuietly(session, name, secret),
          MailSession.establishQuietly(session, name, secret),
        ]);
      }
      session.coordinator.requireCurrent(epoch);
      if (!mounted) return;
      password.clear();
      HapticFeedback.mediumImpact();
      if (widget.onSignedIn != null) {
        widget.onSignedIn!();
      } else if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        phase = _Phase.form;
        showPage = false;
        web = null;
      });
      await showRejection(
        SchoolLoginRejected(
          SchoolLoginRejection.other,
          '登入驗證未完成',
          '$error'.contains('切換帳號')
              ? '要切換帳號，請先到設定登出。'
              : '無法確認校務登入憑證，請確認網路後重新登入。',
        ),
      );
    }
  }

  Future<void> showRejection(SchoolLoginRejected outcome) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(outcome.title),
      content: Text(
        outcome.kind == SchoolLoginRejection.passwordExpired
            ? '${outcome.message}\n\n請先修改密碼後再登入。'
            : outcome.message,
      ),
      actions: [
        if (outcome.kind == SchoolLoginRejection.passwordExpired)
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              openPublicUrl(
                context,
                Uri.parse('https://ccsys.niu.edu.tw/SSO/ChgPwd.aspx'),
              );
            },
            child: const Text('修改密碼'),
          ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('確定'),
        ),
      ],
    ),
  );

  void cancel() {
    revealTimer?.cancel();
    driver?.cancel();
  }

  @override
  Widget build(BuildContext context) {
    final busy = phase != _Phase.form;
    return PopScope(
      canPop: !busy,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) cancel();
      },
      child: Scaffold(
        appBar: NiuAppBar(
          title: showPage ? '校方登入頁' : '登入',
          actions: [
            if (busy && phase == _Phase.signingIn && showPage)
              TextButton(onPressed: cancel, child: const Text('取消')),
          ],
        ),
        body: Stack(
          fit: StackFit.expand,
          children: [
            // The review demo never opens the school login page.
            if (busy && driver != null) _schoolPage(),
            if (!busy) _form(context),
            if (busy && !showPage) _cover(context),
          ],
        ),
      ),
    );
  }

  Widget _schoolPage() {
    final active = driver!;
    return Opacity(
      opacity: showPage ? 1 : 0,
      child: IgnorePointer(
        ignoring: !showPage,
        child: InAppWebView(
          key: ObjectKey(active),
          initialUrlRequest: URLRequest(url: WebUri('$schoolLoginUri')),
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            useShouldOverrideUrlLoading: true,
            allowFileAccess: false,
          ),
          onWebViewCreated: (controller) {
            web = controller;
            active.attach(controller);
          },
          onLoadStart: (_, _) => active.pageStarted(),
          onLoadStop: (_, _) => active.tick(),
          shouldOverrideUrlLoading: (_, action) async {
            if (action.isForMainFrame == false) {
              return NavigationActionPolicy.ALLOW;
            }
            final uri = Uri.tryParse(action.request.url?.toString() ?? '');
            return uri != null && PortalPolicy.academic.allows(uri)
                ? NavigationActionPolicy.ALLOW
                : NavigationActionPolicy.CANCEL;
          },
          onReceivedError: (_, request, _) {
            if (request.isForMainFrame == true) {
              active.finish(
                const SchoolLoginRejected(
                  SchoolLoginRejection.unavailable,
                  '登入頁載入失敗',
                  '無法載入校方登入頁，請確認網路後再試一次。',
                ),
              );
            }
          },
        ),
      ),
    );
  }

  Widget _cover(BuildContext context) => ColoredBox(
    color: Theme.of(context).scaffoldBackgroundColor,
    child: Center(
      child: SingleChildScrollView(
        child: NiuEmpty(
          icon: NiuIcons.lock,
          tone: NiuTone.accent,
          title: phase == _Phase.connecting ? '正在連接 M 園區與活動報名' : '正在登入校務系統',
          message: phase == _Phase.connecting
              ? '校務登入成功，正在完成其他服務的登入。'
              : '正在連線至學校 SSO。若需要人機驗證，會顯示學校的登入頁。',
          action: const SizedBox.square(
            dimension: 28,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          secondaryAction: phase == _Phase.signingIn
              ? Wrap(
                  alignment: WrapAlignment.center,
                  children: [
                    TextButton(
                      onPressed: () => setState(() => showPage = true),
                      child: const Text('開啟校方登入頁'),
                    ),
                    TextButton(onPressed: cancel, child: const Text('取消')),
                  ],
                )
              : null,
        ),
      ),
    ),
  );

  Widget _form(BuildContext context) {
    final theme = Theme.of(context);
    final colors = NiuColors.of(context);
    return SafeArea(
      top: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          NiuSpacing.gutter,
          NiuSpacing.xxl,
          NiuSpacing.gutter,
          NiuSpacing.huge,
        ),
        children: [
          Center(
            child: Container(
              width: 88,
              height: 88,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.accentSoft,
                shape: BoxShape.circle,
              ),
              child: Text(
                'NIU',
                style: theme.textTheme.titleLarge?.copyWith(
                  color: colors.accent,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(height: NiuSpacing.lg),
          Text(
            'NIU-Life',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineLarge,
          ),
          const SizedBox(height: NiuSpacing.xs),
          Text(
            '國立宜蘭大學校園助理',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.inkSecondary,
            ),
          ),
          const SizedBox(height: NiuSpacing.huge),
          Text('帳號密碼與校務系統相同', style: theme.textTheme.bodySmall),
          const SizedBox(height: NiuSpacing.md),
          TextField(
            controller: account,
            keyboardType: TextInputType.visiblePassword,
            textInputAction: TextInputAction.next,
            autocorrect: false,
            enableSuggestions: false,
            autofillHints: const [AutofillHints.username],
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')),
            ],
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => passwordFocus.requestFocus(),
            decoration: const InputDecoration(
              hintText: '學號',
              prefixIcon: Icon(NiuIcons.person),
            ),
          ),
          const SizedBox(height: NiuSpacing.md),
          TextField(
            controller: password,
            focusNode: passwordFocus,
            obscureText: obscure,
            textInputAction: TextInputAction.go,
            autocorrect: false,
            enableSuggestions: false,
            autofillHints: const [AutofillHints.password],
            onChanged: (_) => setState(() {
              if (!passwordShort) passwordChecked = false;
            }),
            onSubmitted: (_) => login(),
            decoration: InputDecoration(
              hintText: '密碼',
              helperText: passwordShort && !passwordChecked
                  ? '密碼至少需要 $minPassword 個字元'
                  : null,
              errorText: passwordChecked && passwordShort
                  ? '密碼至少需要 $minPassword 個字元'
                  : null,
              prefixIcon: const Icon(NiuIcons.lock),
              suffixIcon: IconButton(
                tooltip: obscure ? '顯示密碼' : '隱藏密碼',
                onPressed: () => setState(() => obscure = !obscure),
                icon: Icon(
                  obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
              ),
            ),
          ),
          const SizedBox(height: NiuSpacing.xl),
          FilledButton(
            onPressed: valid ? login : null,
            child: const Text('登入'),
          ),
          const SizedBox(height: NiuSpacing.md),
          Text(
            '登入後帳密會加密保存在這台裝置，下次自動登入；可在設定中清除。',
            textAlign: TextAlign.center,
            style: theme.textTheme.labelMedium,
          ),
          const SizedBox(height: NiuSpacing.xxxl),
          Text(
            '本程式為非官方第三方工具，與宜蘭大學官方無關',
            textAlign: TextAlign.center,
            style: theme.textTheme.labelMedium?.copyWith(
              color: colors.inkTertiary,
            ),
          ),
          Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const PrivacyScreen()),
              ),
              child: const Text('隱私權'),
            ),
          ),
        ],
      ),
    );
  }
}
