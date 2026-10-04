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
  for (final img in doc.querySelectorAll('img')) {
    _keepImageShape(img);
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

/// Lets a picture with a set width keep its shape when the screen narrows
/// it. Mail from Word and Outlook pins both sides in the inline style
/// (`width:6.5in;height:3.2in`), which outranks the page's `height:auto`, so
/// the fixed height is dropped and the declared ratio kept for layout.
void _keepImageShape(dom.Element img) {
  final style = <String, String>{};
  for (final part in (img.attributes['style'] ?? '').split(';')) {
    final i = part.indexOf(':');
    if (i > 0) {
      style[part.substring(0, i).trim().toLowerCase()] = part
          .substring(i + 1)
          .trim();
    }
  }
  final width = style['width'] ?? img.attributes['width'];
  if (width == null || width.trim().isEmpty) return;
  // Same-unit sizes only: a style width over an attribute height says nothing.
  final ratio =
      _sizeRatio(style['width'], style['height']) ??
      _sizeRatio(img.attributes['width'], img.attributes['height']);
  style.remove('height');
  img.attributes.remove('height');
  if (ratio != null) style['aspect-ratio'] = ratio;
  img.attributes['style'] = [
    for (final MapEntry(:key, :value) in style.entries) '$key:$value',
  ].join(';');
}

String? _sizeRatio(String? width, String? height) {
  final size = RegExp(r'^\s*(\d+(?:\.\d+)?)\s*(px|in|pt|cm|mm)?\s*$');
  final w = size.firstMatch(width ?? ''), h = size.firstMatch(height ?? '');
  if (w == null || h == null || w[2] != h[2]) return null;
  final ww = double.parse(w[1]!), hh = double.parse(h[1]!);
  return ww > 0 && hh > 0 ? 'auto ${w[1]} / ${h[1]}' : null;
}

/// Whether [html] shows pictures from outside the school.
bool hasRemoteImages(String html) => RegExp(
  r'''<img[^>]+src=["']?https?://(?!ms\.niu\.edu\.tw)''',
  caseSensitive: false,
).hasMatch(html);

/// A full page for [html]. With [fit], a message wider than the screen is
/// scaled down to its width (as mail apps do), so it scrolls with the page
/// instead of fighting it sideways; heights are reported to the app.
///
/// [width] is the view's width in CSS pixels: Android WebView widens its own
/// `innerWidth` to wide content, so the page cannot measure the screen.
String mailDocument(
  String html, {
  required bool remoteImages,
  required bool fit,
  double width = 0,
}) {
  final body = sanitizeMailHtml(html, remoteImages: remoteImages);
  final script = fit
      ? '<script>var VIEW_WIDTH = ${width.floor()};</script>'
            r"""
<script>
(function(){
  var bridge = function(name, value){
    if (window.flutter_inappwebview) window.flutter_inappwebview.callHandler(name, value);
  };
  function report(){
    bridge('height', Math.ceil(document.documentElement.getBoundingClientRect().height));
  }
  function fit(){
    var b = document.body;
    b.style.zoom = '';
    var wide = Math.max(document.documentElement.scrollWidth, b.scrollWidth);
    var view = VIEW_WIDTH || window.innerWidth;
    var z = wide > view + 1 ? view / wide : 1;
    if (z < 1) b.style.zoom = z;
    bridge('fit', z < 1);
    report();
  }
  window.addEventListener('load', fit);
  window.addEventListener('resize', fit);
  Array.prototype.forEach.call(document.images, function(img){
    if (!img.complete) img.addEventListener('load', fit);
  });
  new ResizeObserver(report).observe(document.documentElement);
  fit();
})();
</script>"""
      : '';
  return """<!doctype html><html><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
html,body{margin:0;padding:0;background:#fff;color:#15171c;}
${fit ? 'html{overflow-x:hidden;}' : ''}
body{font:15px/1.55 sans-serif;padding:16px;overflow-wrap:anywhere;}
img{max-width:100%;height:auto;object-fit:contain;}
pre{white-space:pre-wrap;}
blockquote{margin:0 0 0 .8ex;border-left:2px solid #d0d4dc;padding-left:1ex;color:#5a6070;}
a{color:#0a62d0;}
</style></head><body>$body$script</body></html>""";
}

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
    this.onScaled,
  });
  final String html;
  final Map<String, String> cookies;
  final bool showRemoteImages;
  final ValueChanged<String>? onMailto;

  /// Whether the message had to be scaled down to fit the screen.
  final ValueChanged<bool>? onScaled;
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

  String document(double width) => mailDocument(
    widget.html,
    remoteImages: widget.showRemoteImages,
    fit: true,
    width: width,
  );

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
      return LayoutBuilder(
        builder: (context, box) => SizedBox(
          height: height,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(NiuRadius.md),
            child: InAppWebView(
              key: ValueKey((widget.showRemoteImages, box.maxWidth.floor())),
              initialData: InAppWebViewInitialData(
                data: document(box.maxWidth),
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
                disableHorizontalScroll: true,
                supportZoom: false,
                transparentBackground: false,
                thirdPartyCookiesEnabled: false,
              ),
              onWebViewCreated: (web) => web
                ..addJavaScriptHandler(
                  handlerName: 'height',
                  callback: (args) {
                    final value = args.isEmpty ? null : args.first;
                    if (value is num && mounted) {
                      final next = value
                          .toDouble()
                          .clamp(40, 200000)
                          .toDouble();
                      if ((next - height).abs() > 1) {
                        setState(() => height = next);
                      }
                    }
                  },
                )
                ..addJavaScriptHandler(
                  handlerName: 'fit',
                  callback: (args) {
                    if (mounted && args.isNotEmpty) {
                      widget.onScaled?.call(args.first == true);
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
        ),
      );
    },
  );
}

/// A message at its own width, full screen: the only scroller on the page,
/// so wide layouts pan and pinch-zoom smoothly.
class MailOriginalScreen extends StatelessWidget {
  const MailOriginalScreen({
    super.key,
    required this.title,
    required this.html,
    required this.showRemoteImages,
  });
  final String title, html;
  final bool showRemoteImages;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: NiuAppBar(title: title),
    backgroundColor: Colors.white,
    body: SafeArea(
      top: false,
      child: InAppWebView(
        initialData: InAppWebViewInitialData(
          data: mailDocument(html, remoteImages: showRemoteImages, fit: false),
          baseUrl: WebUri('${NumailClient.origin}/'),
          encoding: 'utf-8',
          mimeType: 'text/html',
        ),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: false,
          supportMultipleWindows: false,
          useShouldOverrideUrlLoading: true,
          allowFileAccess: false,
          allowContentAccess: false,
          supportZoom: true,
          builtInZoomControls: true,
          displayZoomControls: false,
          useWideViewPort: true,
          loadWithOverviewMode: true,
          thirdPartyCookiesEnabled: false,
        ),
        shouldOverrideUrlLoading: (_, action) async {
          final uri = Uri.tryParse(action.request.url.toString());
          if (uri == null || action.isForMainFrame != true) {
            return NavigationActionPolicy.CANCEL;
          }
          if (uri.scheme == 'about' || uri.scheme == 'data') {
            return NavigationActionPolicy.ALLOW;
          }
          if (context.mounted &&
              (uri.scheme == 'https' || uri.scheme == 'http')) {
            await openPublicUrl(context, uri.replace(scheme: 'https'));
          }
          return NavigationActionPolicy.CANCEL;
        },
      ),
    ),
  );
}
