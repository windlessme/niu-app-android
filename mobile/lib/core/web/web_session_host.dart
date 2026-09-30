import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../../shared/shared.dart';

import 'portal_policy.dart';

/// Foreground, visible portal host. It never infers login or attendance success
/// from page loading; those outcomes belong to the service adapter.
class WebSessionHost extends StatefulWidget {
  const WebSessionHost({
    super.key,
    required this.initialUri,
    required this.policy,
    required this.title,
  });

  final Uri initialUri;
  final PortalPolicy policy;
  final String title;

  @override
  State<WebSessionHost> createState() => _WebSessionHostState();
}

class _WebSessionHostState extends State<WebSessionHost> {
  double progress = 0;
  bool failed = false;

  @override
  Widget build(BuildContext context) {
    if (!widget.policy.allows(widget.initialUri)) {
      return Scaffold(
        appBar: NiuAppBar(title: widget.title),
        body: const SafeArea(
          child: Center(
            child: NiuEmpty(
              icon: NiuIcons.lock,
              title: '無法開啟這個網址',
              message: '為了保護帳號，App 只開啟學校的網站。',
            ),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: NiuAppBar(title: widget.title),
      body: SafeArea(
        top: false,
        child: Column(
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
                  message: '學校網頁載入失敗，返回後再試一次。',
                ),
              ),
            Expanded(
              child: InAppWebView(
                initialUrlRequest: URLRequest(
                  url: WebUri(widget.initialUri.toString()),
                ),
                initialSettings: InAppWebViewSettings(
                  useShouldOverrideUrlLoading: true,
                  javaScriptEnabled: true,
                  allowFileAccess: false,
                  allowContentAccess: false,
                  supportMultipleWindows: false,
                ),
                shouldOverrideUrlLoading: (controller, action) async {
                  final url = action.request.url;
                  if (url == null ||
                      !widget.policy.allows(Uri.parse(url.toString()))) {
                    return NavigationActionPolicy.CANCEL;
                  }
                  return NavigationActionPolicy.ALLOW;
                },
                onProgressChanged: (_, value) {
                  if (mounted) setState(() => progress = value / 100);
                },
                onReceivedError: (_, request, error) {
                  if (request.isForMainFrame == true && mounted) {
                    setState(() {
                      failed = true;
                      progress = 1;
                    });
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
