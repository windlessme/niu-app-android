import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../../shared/shared.dart';
import '../attendance/attendance_repository.dart';
import 'moodle_repository.dart';

class MoodleWebScreen extends StatefulWidget {
  const MoodleWebScreen({
    super.key,
    required this.repository,
    required this.target,
    required this.title,
    this.attendance = false,
  });
  final MoodleRepository repository;
  final Uri target;
  final String title;
  final bool attendance;
  @override
  State<MoodleWebScreen> createState() => _MoodleWebScreenState();
}

class _MoodleWebScreenState extends State<MoodleWebScreen> {
  late final Future<Uri> entry = _entry();
  Future<Uri> _entry() async {
    try {
      return await widget.repository.webUri(widget.target);
    } catch (_) {
      // Token API and website login are separate. Keep the real school login
      // usable when automatic web-login keys are unavailable.
      if (allowed(widget.target)) return widget.target;
      rethrow;
    }
  }

  AttendanceOutcome? outcome;
  double progress = 0;
  bool failed = false;
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
  Future<void> inspect(InAppWebViewController controller, WebUri? url) async {
    if (!widget.attendance ||
        url == null ||
        Uri.parse('$url').host != 'euni.niu.edu.tw') {
      return;
    }
    if ([
      AttendanceOutcome.recorded,
      AttendanceOutcome.alreadyRecorded,
      AttendanceOutcome.expired,
      AttendanceOutcome.failed,
    ].contains(outcome)) {
      return;
    }
    final raw = await controller.evaluateJavascript(
      source: r'''JSON.stringify({
      body: (document.querySelector('[role="main"],#region-main,main')?.innerText || '').slice(0,12000),
      notifications: Array.from(document.querySelectorAll('[data-region="notification"],[role="alert"],.alert,.notification,.errorbox,.errormessage,[data-rel="fatalerror"],.notifyproblem,.notifysuccess')).map(e=>e.innerText).join('\n'),
      hasForm: Array.from(document.querySelectorAll('form')).some(f => new URL(f.action || location.href, location.href).pathname === '/mod/attendance/attendance.php' && !!f.querySelector('input[name="sessid"]') && !!f.querySelector('input[name="status"],select[name="status"],input[name="studentpassword"]') && !!f.querySelector('button[type="submit"],input[type="submit"]')),
      errorCodes: Array.from(document.querySelectorAll('a[href*="errorcode="],a[href*="/error/"]')).map(e=>new URL(e.href).searchParams.get('errorcode')||e.href.split('/').pop())
    })''',
    );
    if (!mounted || raw is! String) return;
    try {
      final data = object(jsonDecode(raw));
      setState(
        () => outcome = attendanceOutcome(
          original: widget.target,
          response: Uri.parse('$url'),
          body: '${data['body']}',
          notifications: '${data['notifications']}',
          hasForm: data['hasForm'] == true,
          errorCodes: (data['errorCodes'] as List).map((e) => '$e').toList(),
        ),
      );
    } catch (_) {
      if (mounted) setState(() => outcome = AttendanceOutcome.unknown);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: IosPageHeader(title: widget.title),
    body: SafeArea(
      top: false,
      child: FutureBuilder<Uri>(
        future: entry,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('無法建立 M 園區網頁登入，請返回重新登入。'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return Column(
            children: [
              if (progress < 1) LinearProgressIndicator(value: progress),
              if (failed)
                const Padding(
                  padding: EdgeInsets.all(NiuSpacing.xl),
                  child: Text('校方頁面載入失敗，請返回查看紀錄。'),
                ),
              if (outcome != null)
                Padding(
                  padding: const EdgeInsets.all(NiuSpacing.xl),
                  child: Text(switch (outcome!) {
                    AttendanceOutcome.recorded => '點名成功：M 園區已記錄本次出席。',
                    AttendanceOutcome.alreadyRecorded => '本次出席已經記錄。',
                    AttendanceOutcome.expired =>
                      'QR Code 已過期，這次未完成點名。請重新掃描最新 QR Code。',
                    AttendanceOutcome.requiresAction => '請在下方校方頁面選擇狀態或送出表單。',
                    AttendanceOutcome.failed => '本次點名未完成，請查看下方校方說明。',
                    AttendanceOutcome.unknown => '尚未取得可確認的點名結果，請查看校方頁面或出席紀錄。',
                  }),
                ),
              Expanded(
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
                  shouldOverrideUrlLoading: (_, action) async =>
                      action.request.url != null &&
                          allowed(Uri.parse('${action.request.url}'))
                      ? NavigationActionPolicy.ALLOW
                      : NavigationActionPolicy.CANCEL,
                  onProgressChanged: (_, p) {
                    if (mounted) setState(() => progress = p / 100);
                  },
                  onLoadStop: inspect,
                  onReceivedError: (_, request, error) {
                    if (request.isForMainFrame == true && mounted) {
                      setState(() => failed = true);
                    }
                  },
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}
