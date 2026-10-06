import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../../shared/shared.dart';
import 'moodle_repository.dart';
import 'moodle_web_session.dart';

class MoodleWebScreen extends StatefulWidget {
  const MoodleWebScreen({
    super.key,
    required this.repository,
    required this.target,
    required this.title,
  });
  final MoodleRepository repository;
  final Uri target;
  final String title;
  @override
  State<MoodleWebScreen> createState() => _MoodleWebScreenState();
}

class _MoodleWebScreenState extends State<MoodleWebScreen> {
  late final Future<Uri> entry = _entry();
  Future<Uri> _entry() async {
    if (!allowed(widget.target)) {
      throw const FormatException('無法開啟非 M 園區網址');
    }
    try {
      await MoodleWebSession.ensureSignedIn(widget.repository);
    } catch (_) {
      // The school's own login page stays usable when every automatic way
      // fails; the student can still sign in there.
    }
    return widget.target;
  }

  double progress = 0;
  bool failed = false;

  /// One more automatic sign-in when the page still asks to log in, e.g.
  /// after the website session expired on the school's side.
  bool retried = false;

  Future<void> signInAgain(InAppWebViewController web, WebUri? url) async {
    final page = Uri.tryParse('$url');
    if (retried || page == null || page.host != 'euni.niu.edu.tw') return;
    final login = await web.evaluateJavascript(
      source:
          "!!document.querySelector('#login input[name=\"password\"], #page-login-index')",
    );
    if (login != true || retried || !mounted) return;
    retried = true;
    try {
      await MoodleWebSession.ensureSignedIn(widget.repository, force: true);
    } catch (_) {
      return;
    }
    if (mounted) {
      await web.loadUrl(
        urlRequest: URLRequest(url: WebUri('${widget.target}')),
      );
    }
  }

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
                    message: '網頁載入失敗，返回後再試一次。',
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
                  onLoadStop: signInAgain,
                  onProgressChanged: (_, p) {
                    if (mounted) setState(() => progress = p / 100);
                  },
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
