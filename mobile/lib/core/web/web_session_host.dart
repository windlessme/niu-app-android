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
        appBar: IosPageHeader(title: widget.title),
        body: const SafeArea(child: Center(child: Text('無法開啟此校務網址'))),
      );
    }
    return Scaffold(
      appBar: IosPageHeader(title: widget.title),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            if (progress < 1) LinearProgressIndicator(value: progress),
            if (failed)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text('校方頁面無法載入，請返回後重試。'),
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
