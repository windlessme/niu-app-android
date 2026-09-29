import 'dart:async';
import 'dart:convert';
import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../../shared/shared.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../../features/authentication/login_screen.dart';
import '../session/campus_session.dart';
import 'portal_policy.dart';
import 'academic_portal_scripts.dart';

/// Visible school-page fallback and an optional native presentation of its DOM.
/// All frames use the platform's shared cookie store, including SSO and Moodle.
class AcademicPortalScreen extends StatefulWidget {
  const AcademicPortalScreen({
    super.key,
    required this.title,
    this.target,
    this.menuLabel,
    this.extractScript,
    this.snapshotBuilder,
    this.prepareScript,
    this.session,
    this.bridge = true,
    this.entryBuilder,
    this.navigationScript,
    this.onSnapshot,
    this.referer,
    this.webViewBuilder,
    this.loadTimeout = const Duration(seconds: 60),
  });
  final String title;
  final Uri? target;
  final Uri? referer;

  /// Test seam; lazily creates the platform view only on supported platforms.
  final Widget Function(Widget Function() create)? webViewBuilder;
  final Duration loadTimeout;
  final String? menuLabel;
  final String? extractScript;
  final String? prepareScript;
  final Widget Function(BuildContext, dynamic)? snapshotBuilder;
  final CampusSession? session;
  final bool bridge;
  final Future<Uri> Function(CampusSession session)? entryBuilder;
  final String? navigationScript;
  final Future<void> Function(dynamic value, int epoch)? onSnapshot;
  @override
  State<AcademicPortalScreen> createState() => _AcademicPortalScreenState();
}

class _AcademicPortalScreenState extends State<AcademicPortalScreen> {
  late final session = widget.session ?? CampusSession.instance;
  InAppWebViewController? controller;
  Uri? entry;
  dynamic snapshot;
  String? error;
  bool schoolPage = false;
  int? pollingGeneration;
  bool menuClicked = false;
  bool loading = true;
  int generation = 0;
  int epoch = 0;
  int attempts = 0;
  Timer? timer;
  Timer? deadline;
  final Set<String> navigated = {};
  bool targetReady = false;
  bool eventLoginRequired = false;
  late String readRun;

  @override
  void initState() {
    super.initState();
    session.addListener(sessionChanged);
    session.registerCleanup(clearWebData);
    start();
  }

  void sessionChanged() {
    if (session.coordinator.epoch != epoch && mounted) {
      timer?.cancel();
      deadline?.cancel();
      generation++;
      setState(() {
        snapshot = null;
        entry = null;
        error = '已登出，請重新登入';
        loading = false;
      });
    }
  }

  Future<void> clearWebData() async {
    await controller?.stopLoading();
    await controller?.evaluateJavascript(
      source: 'sessionStorage.clear(); localStorage.clear();',
    );
  }

  Future<void> start() async {
    final current = ++generation;
    readRun = '$current-${DateTime.now().microsecondsSinceEpoch}';
    epoch = session.coordinator.epoch;
    timer?.cancel();
    deadline?.cancel();
    controller = null;
    navigated.clear();
    targetReady = false;
    eventLoginRequired = false;
    deadline = Timer(widget.loadTimeout, () {
      if (!mounted || current != generation) return;
      timer?.cancel();
      setState(() {
        loading = false;
        error = '資料載入逾時，可重試或開啟校方頁面。';
        schoolPage = true;
      });
    });
    if (mounted) {
      setState(() {
        error = null;
        loading = true;
        snapshot = null;
        entry = null;
      });
    }
    menuClicked = false;
    attempts = 0;
    try {
      final uri = widget.entryBuilder != null
          ? await widget.entryBuilder!(session)
          : widget.bridge
          ? await session.academicEntry()
          : widget.target!;
      if (!mounted || current != generation) return;
      if (!loading) return;
      session.coordinator.requireCurrent(epoch);
      setState(() => entry = uri);
      timer = Timer.periodic(const Duration(milliseconds: 750), (_) => poll());
    } catch (_) {
      if (mounted && current == generation) {
        deadline?.cancel();
        setState(() {
          error = '校務連線未完成，請登入後重試。';
          loading = false;
        });
      }
    }
  }

  Future<void> poll() async {
    if (pollingGeneration == generation ||
        controller == null ||
        !mounted ||
        snapshot != null ||
        error != null) {
      return;
    }
    final current = generation;
    pollingGeneration = current;
    try {
      session.coordinator.requireCurrent(epoch);
      final web = controller!;
      if (widget.bridge || widget.navigationScript != null) {
        final navigation = await web.evaluateJavascript(
          source:
              widget.navigationScript ??
              academicNavigationScript(widget.target),
        );
        if (!mounted || current != generation || error != null) return;
        if (navigation == 'login-required') {
          deadline?.cancel();
          if (!eventLoginRequired) {
            // A prior attempt to visit ApplyMe may have redirected to login.
            // Permit that same destination once authentication has completed.
            navigated.clear();
            targetReady = false;
            setState(() {
              eventLoginRequired = true;
              loading = false;
              schoolPage = true;
            });
          }
          return;
        }
        if (eventLoginRequired && navigation != null) {
          setState(() {
            eventLoginRequired = false;
            loading = true;
            schoolPage = false;
          });
          deadline = Timer(widget.loadTimeout, () {
            if (!mounted || current != generation) return;
            timer?.cancel();
            setState(() {
              loading = false;
              error = '資料載入逾時，可重試或開啟校方頁面。';
              schoolPage = true;
            });
          });
        }
        if (navigation == 'ready') {
          targetReady = true;
          if (widget.extractScript == null) {
            deadline?.cancel();
            timer?.cancel();
            setState(() => loading = false);
          }
        } else if (navigation is String) {
          targetReady = false;
          final next = Uri.tryParse(navigation);
          if (next != null &&
              PortalPolicy.academic.allows(next) &&
              navigated.add(next.toString())) {
            await web.loadUrl(
              urlRequest: URLRequest(
                url: WebUri(next.toString()),
                headers: next == widget.target && widget.bridge
                    ? {
                        'Referer':
                            (widget.referer ??
                                    Uri.parse(
                                      'https://acade.niu.edu.tw/NIU/MainFrame.aspx',
                                    ))
                                .toString(),
                      }
                    : null,
              ),
            );
            return;
          }
        } else {
          targetReady = false;
        }
      } else {
        targetReady = true;
      }
      if (++attempts > 80) {
        timer?.cancel();
        if (mounted) {
          setState(() {
            loading = false;
            error = '資料載入逾時，可重試或開啟校方頁面。';
            schoolPage = true;
          });
        }
        return;
      }
      if (widget.menuLabel != null && !menuClicked) {
        final result = await controller!.evaluateJavascript(
          source: academicMenuScript(widget.menuLabel!),
        );
        menuClicked = result == true;
      }
      if (widget.extractScript == null) return;
      if (widget.target != null && !targetReady) return;
      final value = await web.evaluateJavascript(
        source: academicReadScript(
          extract: widget.extractScript!,
          prepare: widget.prepareScript,
          run: readRun,
        ),
      );
      if (!mounted || current != generation || error != null) return;
      if (value is String && value.isNotEmpty && value != 'null') {
        final envelope = jsonDecode(value) as Map<String, dynamic>;
        final identity = await web.evaluateJavascript(
          source: academicDocumentIdentityScript(readRun),
        );
        if (!mounted ||
            current != generation ||
            error != null ||
            envelope['signature'] != identity) {
          return;
        }
        final parsed = jsonDecode(envelope['value'] as String);
        if (parsed != null &&
            mounted &&
            current == generation &&
            error == null) {
          session.coordinator.requireCurrent(epoch);
          await widget.onSnapshot?.call(parsed, epoch);
          if (!mounted || current != generation || error != null) return;
          setState(() {
            snapshot = parsed;
            loading = false;
            error = null;
          });
          timer?.cancel();
          deadline?.cancel();
        }
      }
    } catch (_) {
      // Frames can navigate independently; bounded polling retries their DOM.
    } finally {
      if (pollingGeneration == current) pollingGeneration = null;
    }
  }

  Future<void> loaded(InAppWebViewController web, WebUri? url) async {
    if (!mounted || url == null || web != controller || error != null) return;
    final current = generation;
    final uri = Uri.parse(url.toString());
    if (widget.bridge && isAcademicSessionExpired(uri)) {
      timer?.cancel();
      deadline?.cancel();
      if (!mounted || current != generation) return;
      setState(() {
        loading = false;
        error = '登入已過期，請重新登入';
        schoolPage = true;
      });
      return;
    }
    if (widget.extractScript == null &&
        widget.navigationScript == null &&
        mounted) {
      deadline?.cancel();
      setState(() => loading = false);
    }
    await poll();
  }

  @override
  void dispose() {
    generation++;
    timer?.cancel();
    deadline?.cancel();
    session.removeListener(sessionChanged);
    session.unregisterCleanup(clearWebData);
    controller?.stopLoading();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewGeneration = generation;
    return Scaffold(
      appBar: IosPageHeader(
        title: widget.title,
        actions: [
          if (widget.extractScript != null)
            CircleIconButton(
              label: schoolPage ? 'App 檢視' : '查看資料來源',
              icon: schoolPage
                  ? CupertinoIcons.square_grid_2x2
                  : CupertinoIcons.globe,
              onPressed: () => setState(() => schoolPage = !schoolPage),
            ),
          CircleIconButton(
            label: '重新整理',
            icon: CupertinoIcons.arrow_clockwise,
            onPressed: start,
          ),
        ],
      ),
      body: Column(
        children: [
          if (eventLoginRequired)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  const Text('活動登入尚未建立或已過期。重新連接校務登入後，會自動返回此活動頁面。'),
                  TextButton(
                    onPressed: () async {
                      final ok = await Navigator.of(context).push<bool>(
                        MaterialPageRoute(
                          builder: (_) => LoginScreen(session: session),
                        ),
                      );
                      if (ok == true && mounted) start();
                    },
                    child: const Text('重新連接活動登入'),
                  ),
                ],
              ),
            ),
          if (loading)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Row(
                children: [
                  CupertinoActivityIndicator(),
                  SizedBox(width: 12),
                  Expanded(child: Text('正在連線校務系統並讀取資料…')),
                ],
              ),
            ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Text(error!),
                  TextButton(
                    onPressed: () async {
                      final ok = await Navigator.of(context).push<bool>(
                        MaterialPageRoute(
                          builder: (_) => LoginScreen(session: session),
                        ),
                      );
                      if (ok == true && mounted) start();
                    },
                    child: const Text('登入校務帳號'),
                  ),
                ],
              ),
            ),
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (entry != null)
                  Offstage(
                    offstage:
                        snapshot != null &&
                        !schoolPage &&
                        widget.snapshotBuilder != null,
                    child: buildWebView(
                      () => InAppWebView(
                        key: ValueKey(generation),
                        initialUrlRequest: URLRequest(
                          url: WebUri(entry.toString()),
                        ),
                        initialSettings: InAppWebViewSettings(
                          javaScriptEnabled: true,
                          useShouldOverrideUrlLoading: true,
                          supportMultipleWindows: true,
                          javaScriptCanOpenWindowsAutomatically: true,
                          allowFileAccess: false,
                        ),
                        initialUserScripts: widget.extractScript == null
                            ? null
                            : UnmodifiableListView([
                                UserScript(
                                  source: academicFrameSnapshotScript(
                                    widget.extractScript!,
                                  ),
                                  injectionTime:
                                      UserScriptInjectionTime.AT_DOCUMENT_END,
                                  forMainFrameOnly: false,
                                ),
                              ]),
                        onWebViewCreated: (web) {
                          if (!mounted || viewGeneration != generation) return;
                          controller = web;
                          final captured = viewGeneration;
                          web.addJavaScriptHandler(
                            handlerName: 'academicSnapshot',
                            callback: (arguments) async {
                              if (!mounted ||
                                  captured != generation ||
                                  session.coordinator.epoch != epoch ||
                                  error != null ||
                                  snapshot != null ||
                                  arguments.isEmpty) {
                                return;
                              }
                              // Frame messages are wakeups, never authoritative
                              // data: a queued message may belong to an old DOM.
                              await poll();
                            },
                          );
                        },
                        onLoadStop: loaded,
                        onLoadStart: (web, _) {
                          if (web == controller) targetReady = false;
                        },
                        onCreateWindow: (web, action) async {
                          if (web != controller ||
                              viewGeneration != generation) {
                            return false;
                          }
                          final uri = Uri.tryParse(
                            action.request.url?.toString() ?? '',
                          );
                          if (uri != null &&
                              PortalPolicy.academic.allows(uri)) {
                            await web.loadUrl(
                              urlRequest: URLRequest(
                                url: WebUri(uri.toString()),
                              ),
                            );
                          }
                          return false;
                        },
                        shouldOverrideUrlLoading: (_, action) async {
                          if (action.isForMainFrame == false) {
                            return NavigationActionPolicy.ALLOW;
                          }
                          final uri = Uri.tryParse(
                            action.request.url?.toString() ?? '',
                          );
                          return uri != null &&
                                  (uri.toString() == 'about:blank' ||
                                      PortalPolicy.academic.allows(uri))
                              ? NavigationActionPolicy.ALLOW
                              : NavigationActionPolicy.CANCEL;
                        },
                        onReceivedError: (web, request, failure) {
                          if (web == controller &&
                              request.isForMainFrame == true &&
                              mounted) {
                            deadline?.cancel();
                            timer?.cancel();
                            setState(() {
                              error = '校方頁面載入失敗，請檢查網路後重試。';
                              loading = false;
                            });
                          }
                        },
                      ),
                    ),
                  ),
                if (snapshot != null &&
                    !schoolPage &&
                    widget.snapshotBuilder != null)
                  Positioned.fill(
                    child: ColoredBox(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      child: widget.snapshotBuilder!(context, snapshot),
                    ),
                  ),
                if (entry == null && error == null)
                  const Center(child: CircularProgressIndicator()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget buildWebView(Widget Function() create) =>
      widget.webViewBuilder?.call(create) ?? create();
}

bool isAcademicSessionExpired(Uri uri) {
  if (!PortalPolicy.academic.allows(uri)) return false;
  final path = uri.path.toLowerCase();
  if (uri.host == 'ccsys1.niu.edu.tw' &&
      (path == '/sso' || path.startsWith('/sso/'))) {
    return true;
  }
  final guid = uri.queryParameters.entries.any(
    (e) => e.key.toLowerCase() == 'guid' && e.value.isNotEmpty,
  );
  return path.endsWith('/timeoutpage.aspx') ||
      path.endsWith('/default.aspx') ||
      (path.endsWith('/login.aspx') && !guid) ||
      path.endsWith('/account/login');
}

/// Recurses same-origin frames like iOS; inaccessible cross-origin frames are skipped.
const portalDocumentCollector = r'''
const docs = [];
function collect(w) { try { docs.push(w.document); for(let i=0;i<w.frames.length;i++) collect(w.frames[i]); } catch (_) {} }
collect(window);
const clean = value => String(value || '').replace(/\s+/g, ' ').trim();
''';
