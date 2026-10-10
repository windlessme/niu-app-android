import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/analytics/app_analytics.dart';
import '../../shared/shared.dart';
import '../moodle/moodle_repository.dart';
import 'attendance_repository.dart';
import '../moodle/moodle_demo.dart';
import '../../core/demo/demo_account.dart';

/// Reads the page Moodle returns after an attendance link is opened.
const attendanceInspectScript = r'''JSON.stringify({
  body: (document.querySelector('[role="main"],#region-main,main')?.innerText || '').slice(0,12000),
  notifications: Array.from(document.querySelectorAll('[data-region="notification"],[role="alert"],.alert,.notification,.errorbox,.errormessage,[data-rel="fatalerror"],.notifyproblem,.notifysuccess')).map(e=>e.innerText).join('\n'),
  hasForm: Array.from(document.querySelectorAll('form')).some(f => new URL(f.action || location.href, location.href).pathname === '/mod/attendance/attendance.php' && !!f.querySelector('input[name="sessid"]') && !!f.querySelector('input[name="status"],select[name="status"],input[name="studentpassword"]') && !!f.querySelector('button[type="submit"],input[type="submit"]')),
  errorCodes: Array.from(document.querySelectorAll('a[href*="errorcode="],a[href*="/error/"]')).map(e=>new URL(e.href).searchParams.get('errorcode')||e.href.split('/').pop())
})''';

enum _Verification { idle, checking, verified, warning }

/// Native summary of one QR attendance attempt, backed by a live M 園區
/// page that can be shown on demand (or automatically when the school asks
/// the student to choose a status).
class AttendanceResultScreen extends StatefulWidget {
  const AttendanceResultScreen({
    super.key,
    required this.repository,
    required this.target,
    this.onExpired,
  });
  final MoodleRepository repository;

  /// A link already validated by [attendanceQr].
  final Uri target;
  final VoidCallback? onExpired;

  @override
  State<AttendanceResultScreen> createState() => _AttendanceResultScreenState();
}

class _AttendanceResultScreenState extends State<AttendanceResultScreen> {
  late final Future<Uri> entry = _entry();
  InAppWebViewController? controller;
  AttendanceOutcome? outcome;
  String message = '';
  String? error;
  bool showWeb = false;
  bool shareDismissed = false;
  bool verifying = false;
  _Verification verification = _Verification.idle;
  String verificationText = '';
  DateTime? resolvedAt;
  Timer? timeout;

  Future<Uri> _entry() async {
    try {
      return await widget.repository.webUri(widget.target);
    } catch (_) {
      // Token API and website login are separate; the school login page
      // remains usable when automatic web login keys are unavailable.
      return widget.target;
    }
  }

  /// Review demo: a simulated success, never a request to M 園區.
  bool get demo => widget.repository is DemoMoodleRepository;

  @override
  void initState() {
    super.initState();
    if (demo) {
      outcome = AttendanceOutcome.recorded;
      message = storeScreenshots
          ? _defaultMessage(AttendanceOutcome.recorded)
          : '示範模式：已模擬點名，沒有連線到 M 園區。';
      resolvedAt = DateTime.now();
      return;
    }
    _armTimeout();
  }

  void _armTimeout() {
    timeout?.cancel();
    timeout = Timer(const Duration(seconds: 45), () {
      if (!mounted) return;
      if (verifying) {
        setState(() {
          verifying = false;
          verification = _Verification.warning;
          verificationText = 'M 園區沒有回應，無法確認。';
        });
      } else if (outcome == null && error == null) {
        setState(() {
          outcome = AttendanceOutcome.unknown;
          message = 'M 園區沒有回應。請查看 M 園區回應，或到出席紀錄確認。';
        });
      }
    });
  }

  @override
  void dispose() {
    // One report per scan, with the result the student last saw.
    AppAnalytics.instance.event('attendance', {
      'outcome': outcome?.name ?? 'no_answer',
    });
    timeout?.cancel();
    controller?.stopLoading();
    super.dispose();
  }

  bool get success =>
      outcome == AttendanceOutcome.recorded ||
      outcome == AttendanceOutcome.alreadyRecorded;

  bool allowed(Uri u) =>
      u.scheme == 'https' &&
      u.port == 443 &&
      u.userInfo.isEmpty &&
      const {
        'euni.niu.edu.tw',
        'sso.niu.edu.tw',
        'ccsys.niu.edu.tw',
        'ccsys1.niu.edu.tw',
      }.contains(u.host);

  static String _defaultMessage(AttendanceOutcome value) => switch (value) {
    AttendanceOutcome.recorded => 'M 園區已記錄這次出席。',
    AttendanceOutcome.alreadyRecorded => '這個時段的出席先前已經記錄。',
    AttendanceOutcome.expired => '請掃描老師目前顯示的最新 QR Code。',
    AttendanceOutcome.failed => 'M 園區沒有記錄這次點名。',
    AttendanceOutcome.unknown => 'M 園區沒有回傳可確認的結果。',
    AttendanceOutcome.requiresAction => '請在 M 園區頁面選擇出席狀態後送出。',
  };

  Future<void> inspect(InAppWebViewController web, WebUri? url) async {
    if (url == null || Uri.parse('$url').host != 'euni.niu.edu.tw') return;
    final raw = await web.evaluateJavascript(source: attendanceInspectScript);
    if (!mounted || raw is! String) return;
    AttendanceOutcome next;
    var notice = '';
    try {
      final data = object(jsonDecode(raw));
      notice = '${data['notifications']}'
          .split('\n')
          .map((l) => l.trim())
          .firstWhere((l) => l.isNotEmpty, orElse: () => '');
      next = attendanceOutcome(
        original: widget.target,
        response: Uri.parse('$url'),
        body: '${data['body']}',
        notifications: '${data['notifications']}',
        hasForm: data['hasForm'] == true,
        errorCodes: (data['errorCodes'] as List).map((e) => '$e').toList(),
      );
    } catch (_) {
      next = AttendanceOutcome.unknown;
    }
    // Pages loaded after a confirmed result (redirects, view page) must not
    // downgrade it to "unknown".
    if (!verifying &&
        success &&
        (next == AttendanceOutcome.unknown ||
            next == AttendanceOutcome.requiresAction)) {
      return;
    }
    if (next == AttendanceOutcome.expired) widget.onExpired?.call();
    if (verifying) {
      timeout?.cancel();
      setState(() {
        verifying = false;
        switch (next) {
          case AttendanceOutcome.recorded || AttendanceOutcome.alreadyRecorded:
            verification = _Verification.verified;
            verificationText = '已用同一個登入重新向 M 園區查核';
            showWeb = false;
          case AttendanceOutcome.requiresAction:
            verification = _Verification.warning;
            verificationText = 'M 園區仍顯示可填寫的表單，無法確認這次點名已寫入。';
            showWeb = true;
          case AttendanceOutcome.unknown:
            verification = _Verification.warning;
            verificationText = 'M 園區沒有回傳可確認的驗證結果。';
          case _:
            verification = _Verification.warning;
            verificationText = notice.isEmpty ? _defaultMessage(next) : notice;
        }
      });
      if (verification == _Verification.verified) {
        HapticFeedback.mediumImpact();
      }
      return;
    }
    // "Unknown" while pages are still redirecting is not a result yet.
    if (next == AttendanceOutcome.unknown && outcome == null) return;
    timeout?.cancel();
    setState(() {
      outcome = next;
      message = notice.isEmpty ? _defaultMessage(next) : notice;
      resolvedAt = DateTime.now();
      if (next == AttendanceOutcome.requiresAction) showWeb = true;
    });
    if (next != AttendanceOutcome.requiresAction) {
      success ? HapticFeedback.mediumImpact() : HapticFeedback.heavyImpact();
    }
  }

  void verify() {
    if (demo) {
      setState(() {
        verification = _Verification.verified;
        verificationText = storeScreenshots
            ? '已用同一個登入重新向 M 園區查核'
            : '示範模式：模擬查核完成';
      });
      return;
    }
    final web = controller;
    if (web == null || verifying) return;
    setState(() {
      verifying = true;
      verification = _Verification.checking;
    });
    _armTimeout();
    web.loadUrl(urlRequest: URLRequest(url: WebUri('${widget.target}')));
  }

  void goHome() {
    final router = GoRouter.maybeOf(context);
    Navigator.of(context).popUntil((route) => route.isFirst);
    router?.go('/');
  }

  Future<void> share() async {
    setState(() => shareDismissed = true);
    HapticFeedback.lightImpact();
    try {
      await SharePlus.instance.share(ShareParams(text: '${widget.target}'));
    } catch (_) {
      if (mounted) showNiuMessage(context, '無法分享連結');
    }
  }

  @override
  Widget build(BuildContext context) {
    final showShare =
        success && error == null && !shareDismissed && !showWeb && !demo;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: NiuIconButton(
          icon: NiuIcons.homeSelected,
          tooltip: '回到主頁',
          onPressed: goHome,
        ),
        titleSpacing: NiuSpacing.xs,
        title: const Text('點名結果'),
        actions: [
          if (showWeb && outcome != AttendanceOutcome.requiresAction)
            TextButton(
              onPressed: () => setState(() => showWeb = false),
              child: const Text('摘要'),
            ),
          const SizedBox(width: NiuSpacing.xs),
        ],
      ),
      bottomNavigationBar: showShare ? _sharePrompt(context) : null,
      body: SafeArea(
        top: false,
        child: demo
            ? _summary(context)
            : FutureBuilder<Uri>(
                future: entry,
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return _loading(context);
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      Opacity(
                        opacity: showWeb ? 1 : 0,
                        child: IgnorePointer(
                          ignoring: !showWeb,
                          child: InAppWebView(
                            initialUrlRequest: URLRequest(
                              url: WebUri('${snapshot.data}'),
                            ),
                            initialSettings: InAppWebViewSettings(
                              useShouldOverrideUrlLoading: true,
                              javaScriptEnabled: true,
                              allowFileAccess: false,
                              allowContentAccess: true,
                              supportMultipleWindows: false,
                            ),
                            onWebViewCreated: (web) => controller = web,
                            shouldOverrideUrlLoading: (_, action) async =>
                                action.request.url != null &&
                                    allowed(Uri.parse('${action.request.url}'))
                                ? NavigationActionPolicy.ALLOW
                                : NavigationActionPolicy.CANCEL,
                            onLoadStop: inspect,
                            onReceivedError: (_, request, failure) {
                              if (request.isForMainFrame == true &&
                                  mounted &&
                                  outcome == null) {
                                timeout?.cancel();
                                setState(() => error = '無法連上 M 園區，請檢查網路後重新掃描。');
                              }
                            },
                          ),
                        ),
                      ),
                      if (!showWeb)
                        ColoredBox(
                          color: Theme.of(context).scaffoldBackgroundColor,
                          child: error != null
                              ? _result(
                                  context,
                                  icon: NiuIcons.warning,
                                  tone: NiuTone.warning,
                                  title: '無法完成點名',
                                  message: error!,
                                )
                              : outcome == null ||
                                    outcome == AttendanceOutcome.requiresAction
                              ? _loading(context, canShowWeb: true)
                              : _summary(context),
                        ),
                    ],
                  );
                },
              ),
      ),
    );
  }

  Widget _loading(BuildContext context, {bool canShowWeb = false}) => Center(
    child: SingleChildScrollView(
      child: NiuEmpty(
        icon: NiuIcons.attendance,
        tone: NiuTone.accent,
        title: '正在送出點名',
        message: '請不要離開這個畫面，正在等待 M 園區確認。',
        action: const SizedBox.square(
          dimension: 28,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
        secondaryAction: canShowWeb
            ? TextButton(
                onPressed: () => setState(() => showWeb = true),
                child: const Text('查看 M 園區回應'),
              )
            : null,
      ),
    ),
  );

  Widget _summary(BuildContext context) {
    final (icon, tone, title) = switch (outcome!) {
      AttendanceOutcome.recorded => (NiuIcons.success, NiuTone.success, '點名成功'),
      AttendanceOutcome.alreadyRecorded => (
        Icons.verified_rounded,
        NiuTone.success,
        '已完成點名',
      ),
      AttendanceOutcome.expired => (
        NiuIcons.attendance,
        NiuTone.warning,
        'QR Code 已過期',
      ),
      AttendanceOutcome.failed => (NiuIcons.error, NiuTone.error, '點名未完成'),
      _ => (Icons.help_outline_rounded, NiuTone.warning, '無法確認點名結果'),
    };
    return _result(
      context,
      icon: icon,
      tone: tone,
      title: title,
      message: message,
    );
  }

  Widget _result(
    BuildContext context, {
    required IconData icon,
    required NiuTone tone,
    required String title,
    required String message,
  }) {
    final theme = Theme.of(context);
    final canVerify = success && error == null;
    return ListView(
      padding: NiuLayout.page(
        context,
        top: NiuSpacing.xxl,
        bottom: NiuSpacing.huge,
      ),
      children: [
        Center(
          child: Container(
            width: 104,
            height: 104,
            decoration: BoxDecoration(
              color: tone.background(context),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 56, color: tone.foreground(context)),
          ),
        ),
        const SizedBox(height: NiuSpacing.xl),
        Semantics(
          header: true,
          liveRegion: true,
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineMedium,
          ),
        ),
        const SizedBox(height: NiuSpacing.sm),
        Text(
          message,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: NiuColors.of(context).inkSecondary,
          ),
        ),
        const SizedBox(height: NiuSpacing.xxl),
        _detailCard(context, tone, canVerify),
        const SizedBox(height: NiuSpacing.xl),
        if (canVerify)
          FilledButton.icon(
            onPressed: verifying ? null : verify,
            icon: verifying
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.verified_user_outlined),
            label: Text(switch (verification) {
              _Verification.checking => '驗證中',
              _Verification.verified => '重新驗證出席紀錄',
              _ => '驗證出席紀錄',
            }),
          )
        else
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(NiuIcons.attendance),
            label: const Text('重新掃描 QR Code'),
          ),
        if (error == null && !demo) ...[
          const SizedBox(height: NiuSpacing.sm),
          OutlinedButton.icon(
            onPressed: () => setState(() => showWeb = true),
            icon: const Icon(Icons.language_rounded, size: 18),
            label: const Text('查看 M 園區回應'),
          ),
        ],
        if (canVerify) ...[
          const SizedBox(height: NiuSpacing.xs),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: NiuColors.of(context).inkSecondary,
            ),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('返回掃描'),
          ),
        ],
      ],
    );
  }

  Widget _detailCard(BuildContext context, NiuTone tone, bool accepted) {
    final theme = Theme.of(context);
    final time = resolvedAt == null ? '—' : formatTaipeiClock(resolvedAt!);
    final session = widget.target.queryParameters['sessid'] ?? '—';
    return NiuCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.dns_outlined, color: tone.foreground(context)),
              const SizedBox(width: NiuSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('M 園區回應', style: theme.textTheme.titleSmall),
                    Text(
                      accepted ? '伺服器已接受點名，可以再核對出席紀錄' : '伺服器沒有確認這次點名',
                      style: theme.textTheme.labelMedium,
                    ),
                  ],
                ),
              ),
              Icon(
                accepted ? NiuIcons.success : NiuIcons.warning,
                color: tone.foreground(context),
              ),
            ],
          ),
          const Divider(height: NiuSpacing.xl),
          NiuKeyValue(label: '點名時間', value: time),
          NiuKeyValue(label: 'Session', value: session),
          if (verification != _Verification.idle) ...[
            const SizedBox(height: NiuSpacing.sm),
            switch (verification) {
              _Verification.checking => Row(
                children: [
                  const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: NiuSpacing.sm),
                  Text('正在讀取 M 園區出席紀錄', style: theme.textTheme.bodySmall),
                ],
              ),
              _Verification.verified => NiuBanner(
                tone: NiuTone.success,
                icon: Icons.verified_user_rounded,
                title: '已驗證：已寫入',
                message: verificationText,
              ),
              _ => NiuBanner(tone: NiuTone.warning, message: verificationText),
            },
          ],
        ],
      ),
    );
  }

  Widget _sharePrompt(BuildContext context) {
    final theme = Theme.of(context);
    return NiuBottomBar(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(NiuIcons.success, color: NiuColors.of(context).success),
              const SizedBox(width: NiuSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('你已完成點名', style: theme.textTheme.titleSmall),
                    Text('要分享這次的點名連結嗎？', style: theme.textTheme.labelMedium),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: NiuSpacing.md),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => setState(() => shareDismissed = true),
                  child: const Text('不用分享'),
                ),
              ),
              const SizedBox(width: NiuSpacing.md),
              Expanded(
                child: FilledButton.icon(
                  onPressed: share,
                  icon: const Icon(NiuIcons.share, size: 18),
                  label: const Text('分享連結'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
