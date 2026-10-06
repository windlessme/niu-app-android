import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../../shared/shared.dart';
import 'moodle_repository.dart';

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
    try {
      return await widget.repository.webUri(widget.target);
    } catch (_) {
      // Token API and website login are separate. Keep the real school login
      // usable when automatic web-login keys are unavailable.
      if (allowed(widget.target)) return widget.target;
      rethrow;
    }
  }

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
