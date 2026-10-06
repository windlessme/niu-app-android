import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:html/parser.dart' as html;
import '../../shared/shared.dart';
import '../mail/mail_body_view.dart' show sanitizeMailHtml;
import 'moodle_links.dart';
import 'moodle_repository.dart';

/// A Moodle page activity (group lists, notices, reading material) shown in
/// the app, like iOS: the page text and pictures, not its index.html file.
class MoodlePageScreen extends StatefulWidget {
  const MoodlePageScreen({
    super.key,
    required this.repository,
    required this.courseId,
    required this.module,
  });
  final MoodleRepository repository;
  final int courseId;
  final Json module;
  @override
  State<MoodlePageScreen> createState() => _MoodlePageScreenState();
}

class _MoodlePageScreenState extends State<MoodlePageScreen> {
  late Future<(String, Uri)> future = load();

  /// The page's HTML and the address its relative links resolve against.
  Future<(String, Uri)> load() async {
    final module = widget.module;
    final root = Uri.https('euni.niu.edu.tw', '/');
    try {
      final pages = await widget.repository.pages(widget.courseId);
      Json? match;
      for (final test in <bool Function(Json)>[
        (p) => '${p['coursemodule']}' == '${module['id']}',
        (p) => '${p['id']}' == '${module['instance']}',
        (p) => plain(p['name']) == plain(module['name']),
      ]) {
        match ??= pages.where(test).firstOrNull;
      }
      final content = '${match?['content'] ?? ''}'.trim();
      final intro = '${match?['intro'] ?? ''}'.trim();
      if (content.isNotEmpty || intro.isNotEmpty) {
        return ([intro, content].where((s) => s.isNotEmpty).join('<hr>'), root);
      }
    } catch (_) {
      // Fall back to the page's own index.html below.
    }
    for (final file in objects(module['contents'] ?? [])) {
      final url = file['fileurl'];
      if (url is String && '${file['filename']}'.endsWith('.html')) {
        final bytes = await widget.repository.download(url);
        return (utf8.decode(bytes, allowMalformed: true), Uri.parse(url));
      }
    }
    throw const FormatException('這個頁面沒有內容');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: NiuAppBar(title: plain(widget.module['name'])),
    body: SafeArea(
      top: false,
      child: FutureBuilder<(String, Uri)>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: SingleChildScrollView(
                child: NiuError(
                  title: '無法顯示這個頁面',
                  message: '檢查網路連線後再試一次。',
                  onRetry: () => setState(() => future = load()),
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: NiuLoading(message: '正在載入內容'));
          }
          final (source, base) = snapshot.data!;
          return MoodleHtmlView(
            repository: widget.repository,
            html: source,
            base: base,
            title: plain(widget.module['name']),
          );
        },
      ),
    ),
  );
}

/// Moodle HTML (a page, or an .html material) in the app's colours. Scripts
/// and forms are removed; school pictures load with the app's token; links
/// open the way other M 園區 links do.
class MoodleHtmlView extends StatelessWidget {
  const MoodleHtmlView({
    super.key,
    required this.repository,
    required this.html,
    required this.base,
    required this.title,
  });
  final MoodleRepository repository;
  final String html;
  final Uri base;
  final String title;

  /// In dark mode the author's colours are dropped so text stays readable.
  String document(NiuColors colors, {required bool dark}) {
    String hex(Color c) {
      final v = c.toARGB32();
      return 'rgba(${(v >> 16) & 0xff},${(v >> 8) & 0xff},${v & 0xff},'
          '${((v >> 24) & 0xff) / 255})';
    }

    return '''<!doctype html><html><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
html,body{margin:0;padding:0;background:${hex(colors.canvas)};color:${hex(colors.ink)};}
body{font:16px/1.6 sans-serif;padding:16px;overflow-wrap:anywhere;}
img{max-width:100%;height:auto;border-radius:8px;}
a{color:${hex(colors.accent)};}
hr{border:0;border-top:1px solid ${hex(colors.hairline)};margin:20px 0;}
table{display:block;overflow-x:auto;border-collapse:collapse;max-width:100%;margin:12px 0;}
td,th{border:1px solid ${hex(colors.hairline)};padding:6px 10px;vertical-align:top;}
th{background:${hex(colors.fill)};}
pre{white-space:pre-wrap;}
${dark ? 'html,body{color:${hex(colors.ink)} !important;} body *{background-color:transparent !important;color:inherit !important;} body a{color:${hex(colors.accent)} !important;} body th{background:${hex(colors.fill)} !important;}' : ''}
</style></head><body>${moodleHtmlBody(html, base, repository)}</body></html>''';
  }

  @override
  Widget build(BuildContext context) => InAppWebView(
    key: ValueKey(Theme.of(context).brightness),
    initialData: InAppWebViewInitialData(
      data: document(
        NiuColors.of(context),
        dark: Theme.of(context).brightness == Brightness.dark,
      ),
      baseUrl: WebUri('$base'),
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
      transparentBackground: true,
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
      if (context.mounted && (uri.scheme == 'https' || uri.scheme == 'http')) {
        await openMoodleUrl(
          context,
          repository,
          '${uri.scheme == 'http' ? uri.replace(scheme: 'https') : uri}',
          title,
        );
      }
      return NavigationActionPolicy.CANCEL;
    },
  );
}

/// The safe body of [source]: links made absolute, school pictures given the
/// token they need, outside pictures kept only over https.
String moodleHtmlBody(String source, Uri base, MoodleRepository repository) {
  final doc = html.parse(sanitizeMailHtml(source));
  for (final a in doc.querySelectorAll('a[href]')) {
    final target = Uri.tryParse(a.attributes['href']!.trim());
    if (target != null) a.attributes['href'] = '${base.resolveUri(target)}';
  }
  for (final img in doc.querySelectorAll('img')) {
    img.attributes.remove('srcset');
    final raw = Uri.tryParse((img.attributes['src'] ?? '').trim());
    final src = raw == null ? null : base.resolveUri(raw);
    if (src == null || src.scheme != 'https') {
      img.attributes.remove('src');
    } else if (src.host == 'euni.niu.edu.tw' &&
        src.path.contains('pluginfile.php')) {
      try {
        img.attributes['src'] = '${repository.fileUri('$src')}';
      } catch (_) {
        img.attributes.remove('src');
      }
    } else {
      img.attributes['src'] = '$src';
    }
  }
  return doc.body?.innerHtml ?? '';
}
