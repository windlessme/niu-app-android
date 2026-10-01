import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

import '../../shared/shared.dart';
import 'numail_client.dart';

/// Strips scripts, frames, forms and event handlers from a message. The
/// view's own height probe is the only script that runs.
String sanitizeMailHtml(String source, {bool remoteImages = true}) {
  final doc = html.parse(source);
  if (!remoteImages) {
    // Pictures from other sites stay unloaded until the reader asks.
    for (final img in doc.querySelectorAll('img')) {
      final src = img.attributes['src'] ?? '';
      final uri = Uri.tryParse(src.trim());
      if (uri != null &&
          (uri.scheme == 'http' || uri.scheme == 'https') &&
          uri.host != NumailClient.host) {
        img.attributes.remove('src');
        img.attributes.remove('srcset');
      }
    }
  }
  for (final tag in [
    'script',
    'iframe',
    'frame',
    'frameset',
    'object',
    'embed',
    'form',
    'input',
    'button',
    'textarea',
    'select',
    'meta',
    'link',
    'base',
  ]) {
    for (final e in doc.querySelectorAll(tag)) {
      e.remove();
    }
  }
  for (final e in doc.querySelectorAll('*')) {
    final drop = <Object>[
      for (final MapEntry(:key, :value) in e.attributes.entries)
        if ('$key'.toLowerCase().startsWith('on') ||
            (const {
                  'href',
                  'src',
                  'action',
                  'formaction',
                  'xlink:href',
                }.contains('$key'.toLowerCase()) &&
                value.trim().toLowerCase().startsWith('javascript:')))
          key,
    ];
    for (final key in drop) {
      e.attributes.remove(key);
    }
  }
  final body = doc.body;
  return body == null ? '' : body.innerHtml;
}

/// Whether [html] shows pictures from outside the school.
bool hasRemoteImages(String html) => RegExp(
  r'''<img[^>]+src=["']?https?://(?!ms\.niu\.edu\.tw)''',
  caseSensitive: false,
).hasMatch(html);

/// A message body sized to its content. Pictures from other sites stay
/// out of the page until the reader asks, like the school's "ask before
/// showing". (Request interception is not used: on Android it also stops
/// the page's own data from loading.)
class MailBodyView extends StatefulWidget {
  const MailBodyView({
    super.key,
    required this.html,
    required this.cookies,
    required this.showRemoteImages,
    this.onMailto,
  });
  final String html;
  final Map<String, String> cookies;
  final bool showRemoteImages;
  final ValueChanged<String>? onMailto;
  @override
  State<MailBodyView> createState() => _MailBodyViewState();
}

class _MailBodyViewState extends State<MailBodyView> {
  double height = 120;
  late final Future<void> cookiesReady = _cookies();

  Future<void> _cookies() async {
    final manager = CookieManager.instance();
    final url = WebUri(NumailClient.origin);
    for (final e in widget.cookies.entries) {
      if (e.key == 'XSRF-TOKEN') continue;
      await manager.setCookie(
        url: url,
        name: e.key,
        value: e.value,
        isSecure: true,
        isHttpOnly: true,
      );
    }
  }

  String get document {
    final body = sanitizeMailHtml(
      widget.html,
      remoteImages: widget.showRemoteImages,
    );
    return '''<!doctype html><html><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
html,body{margin:0;padding:0;background:#fff;color:#15171c;}
body{font:15px/1.55 sans-serif;padding:16px;overflow-wrap:anywhere;}
img{max-width:100%;height:auto;}
table{max-width:100%;}
pre{white-space:pre-wrap;}
blockquote{margin:0 0 0 .8ex;border-left:2px solid #d0d4dc;padding-left:1ex;color:#5a6070;}
a{color:#0a62d0;}
</style></head><body>$body
<script>
(function(){
  function report(){
    window.flutter_inappwebview.callHandler('height',
      Math.ceil(document.documentElement.getBoundingClientRect().height));
  }
  window.addEventListener('load', report);
  new ResizeObserver(report).observe(document.documentElement);
  report();
})();
</script></body></html>''';
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
    future: cookiesReady,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return SizedBox(
          height: height,
          child: const NiuLoading(message: '正在顯示信件', compact: true),
        );
      }
      return SizedBox(
        height: height,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(NiuRadius.md),
          child: InAppWebView(
            key: ValueKey(widget.showRemoteImages),
            initialData: InAppWebViewInitialData(
              data: document,
              baseUrl: WebUri('${NumailClient.origin}/'),
              encoding: 'utf-8',
              mimeType: 'text/html',
            ),
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              javaScriptCanOpenWindowsAutomatically: false,
              supportMultipleWindows: false,
              useShouldOverrideUrlLoading: true,
              allowFileAccess: false,
              allowContentAccess: false,
              disableVerticalScroll: true,
              disableHorizontalScroll: false,
              supportZoom: false,
              transparentBackground: false,
              thirdPartyCookiesEnabled: false,
            ),
            onWebViewCreated: (web) => web.addJavaScriptHandler(
              handlerName: 'height',
              callback: (args) {
                final value = args.isEmpty ? null : args.first;
                if (value is num && mounted) {
                  final next = value.toDouble().clamp(40, 200000).toDouble();
                  if ((next - height).abs() > 1) setState(() => height = next);
                }
              },
            ),
            shouldOverrideUrlLoading: (_, action) async {
              final uri = Uri.tryParse(action.request.url.toString());
              if (uri == null || action.isForMainFrame != true) {
                return NavigationActionPolicy.CANCEL;
              }
              if (uri.scheme == 'about' || uri.scheme == 'data') {
                return NavigationActionPolicy.ALLOW;
              }
              if (!context.mounted) return NavigationActionPolicy.CANCEL;
              if (uri.scheme == 'mailto') {
                widget.onMailto?.call(uri.path);
              } else if (uri.scheme == 'https' || uri.scheme == 'http') {
                await openPublicUrl(
                  context,
                  uri.scheme == 'http' ? uri.replace(scheme: 'https') : uri,
                );
              }
              return NavigationActionPolicy.CANCEL;
            },
          ),
        ),
      );
    },
  );
}

/// Visible text of a message, for tests and screen readers.
String mailPlainText(String source) {
  final doc = html.parse(source);
  return (doc.body?.nodes ?? const <dom.Node>[])
      .map((n) => n.text ?? '')
      .join(' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
