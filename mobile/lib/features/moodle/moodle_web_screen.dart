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
    appBar: NiuAppBar(title: widget.title),
    body: SafeArea(
      top: false,
      child: FutureBuilder<Uri>(
        future: entry,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: SingleChildScrollView(
                child: NiuError(
                  title: '無法開啟 M 園區網頁',
                  message: '返回後重新登入 M 園區，再試一次。',
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: NiuLoading(message: '正在連線'));
          }
          final result = outcome;
          return Column(
            children: [
              SizedBox(
                height: 2,
                child: progress < 1
                    ? LinearProgressIndicator(
                        value: progress,
                        minHeight: 2,
                        borderRadius: BorderRadius.zero,
                      )
                    : null,
              ),
              if (failed)
                const Padding(
                  padding: EdgeInsets.all(NiuSpacing.gutter),
                  child: NiuBanner(
                    tone: NiuTone.error,
                    message: '網頁載入失敗。返回後可以在出席紀錄確認結果。',
                  ),
                ),
              if (result != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    NiuSpacing.gutter,
                    NiuSpacing.md,
                    NiuSpacing.gutter,
                    NiuSpacing.md,
                  ),
                  child: NiuBanner(
                    tone: switch (result) {
                      AttendanceOutcome.recorded ||
                      AttendanceOutcome.alreadyRecorded => NiuTone.success,
                      AttendanceOutcome.expired ||
                      AttendanceOutcome.failed => NiuTone.error,
                      _ => NiuTone.warning,
                    },
                    title: switch (result) {
                      AttendanceOutcome.recorded => '點名成功',
                      AttendanceOutcome.alreadyRecorded => '已經點過名了',
                      AttendanceOutcome.expired => 'QR Code 已過期',
                      AttendanceOutcome.requiresAction => '還差一步',
                      AttendanceOutcome.failed => '點名沒有完成',
                      AttendanceOutcome.unknown => '還無法確認結果',
                    },
                    message: switch (result) {
                      AttendanceOutcome.recorded => 'M 園區已記錄這次出席。',
                      AttendanceOutcome.alreadyRecorded => '這堂課的出席已經記錄。',
                      AttendanceOutcome.expired => '這次沒有完成點名，請掃描老師最新的 QR Code。',
                      AttendanceOutcome.requiresAction => '請在下方網頁選擇出席狀態或送出表單。',
                      AttendanceOutcome.failed => '請查看下方網頁的說明。',
                      AttendanceOutcome.unknown => '請查看下方網頁，或到出席紀錄確認。',
                    },
                  ),
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
