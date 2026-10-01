import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../shared/shared.dart';
import 'numail_client.dart';

/// The school's own NUMail page inside the app, signed in with the native
/// session's cookies — for settings and anything the native screens lack.
class MailWebScreen extends StatefulWidget {
  const MailWebScreen({super.key, required this.cookies});
  final Map<String, String> cookies;
  @override
  State<MailWebScreen> createState() => _MailWebScreenState();
}

class _MailWebScreenState extends State<MailWebScreen> {
  static final entry = Uri.parse(
    '${NumailClient.origin}/NUMail/Mobile/Box/INBOX',
  );
  late final Future<void> ready = _cookies();
  InAppWebViewController? web;
  double progress = 0;
  bool failed = false, signedOut = false, canGoBack = false;

  Future<void> _cookies() async {
    final manager = CookieManager.instance();
    final url = WebUri(NumailClient.origin);
    for (final e in widget.cookies.entries) {
      await manager.setCookie(
        url: url,
        name: e.key,
        value: e.value,
        path: '/',
        isSecure: true,
        // The site's script reads its own XSRF-TOKEN cookie.
        isHttpOnly: e.key != 'XSRF-TOKEN',
      );
    }
  }

  static bool _school(Uri u) =>
      u.scheme == 'https' &&
      u.host == NumailClient.host &&
      u.userInfo.isEmpty &&
      (!u.hasPort || u.port == 443);

  Future<void> _sync() async {
    final back = await web?.canGoBack() ?? false;
    if (mounted && back != canGoBack) setState(() => canGoBack = back);
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !canGoBack,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) web?.goBack();
    },
    child: Scaffold(
      appBar: NiuAppBar(
        title: '學校信箱網頁',
        actions: [
          NiuIconButton(
            icon: NiuIcons.refresh,
            tooltip: '重新載入',
            onPressed: () => web?.reload(),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: FutureBuilder<void>(
          future: ready,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
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
                if (failed || signedOut)
                  Padding(
                    padding: const EdgeInsets.all(NiuSpacing.gutter),
                    child: NiuBanner(
                      tone: signedOut ? NiuTone.warning : NiuTone.error,
                      message: signedOut
                          ? '網頁版的登入已結束，可直接在頁面上重新登入。'
                          : '網頁載入失敗，請稍後再試。',
                    ),
                  ),
                Expanded(
                  child: InAppWebView(
                    initialUrlRequest: URLRequest(url: WebUri('$entry')),
                    initialSettings: InAppWebViewSettings(
                      useShouldOverrideUrlLoading: true,
                      javaScriptEnabled: true,
                      allowFileAccess: false,
                      allowContentAccess: true,
                      supportMultipleWindows: false,
                      sharedCookiesEnabled: true,
                    ),
                    onWebViewCreated: (controller) => web = controller,
                    shouldOverrideUrlLoading: (_, action) async {
                      final uri = Uri.tryParse('${action.request.url}');
                      if (uri == null) return NavigationActionPolicy.CANCEL;
                      if (_school(uri) ||
                          uri.scheme == 'about' ||
                          uri.scheme == 'blob' ||
                          uri.scheme == 'data') {
                        return NavigationActionPolicy.ALLOW;
                      }
                      // Links in messages leave the mailbox for the browser.
                      if (context.mounted &&
                          (uri.scheme == 'https' || uri.scheme == 'http')) {
                        await openPublicUrl(
                          context,
                          uri.replace(scheme: 'https'),
                        );
                      }
                      return NavigationActionPolicy.CANCEL;
                    },
                    onLoadStop: (_, url) {
                      final path = Uri.tryParse('$url')?.path ?? '';
                      if (mounted) {
                        setState(
                          () => signedOut = path.startsWith('/NUMail/Login'),
                        );
                      }
                      _sync();
                    },
                    onUpdateVisitedHistory: (_, _, _) => _sync(),
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
    ),
  );
}
