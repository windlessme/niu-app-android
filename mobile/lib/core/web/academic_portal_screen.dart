import 'dart:async';
import 'dart:convert';
import 'dart:collection';

import 'package:flutter/material.dart';

import '../../shared/shared.dart';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../features/authentication/login_screen.dart';
import '../../features/authentication/school_reauthorization.dart';
import '../../features/authentication/remember_school_login.dart';
import '../../features/events/event_login_service.dart';
import '../session/campus_session.dart';
import '../session/portal_snapshot_cache.dart';
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
    this.header,
    this.demoSnapshot,
    this.cacheKey,
  });

  /// Keeps the last snapshot under this key (see [PortalSnapshotCache]) and
  /// shows it while a fresh one loads, or instead of an error.
  final String? cacheKey;

  /// Review demo: the value this page's extraction would return. Without it,
  /// the page is unavailable in demo mode; no WebView is ever created.
  final Object? Function()? demoSnapshot;

  /// Persistent control under the top bar (e.g. a view switcher).
  final Widget? header;
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

class _AcademicPortalScreenState extends State<AcademicPortalScreen>
    with WidgetsBindingObserver {
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
  Timer? timer;
  Timer? deadline;
  final loadWatch = Stopwatch();
  bool foreground = true;
  bool routeActive = true;
  bool reusedAcademicSession = false;
  bool reconnecting = false;
  bool interactionRequired = false;
  final Set<String> navigated = {};
  bool targetReady = false;
  bool eventLoginRequired = false;
  bool eventRecoveryAttempted = false;
  late String readRun;
  CachedSnapshot? cached;
  DateTime? snapshotAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    session.addListener(sessionChanged);
    session.registerCleanup(clearWebData);
    start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeActive = ModalRoute.of(context)?.isCurrent ?? true;
    syncWork();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    syncWork();
    if (foreground && routeActive) unawaited(poll());
  }

  void syncWork() {
    final active =
        foreground &&
        routeActive &&
        error == null &&
        snapshot == null &&
        !(targetReady && widget.extractScript == null);
    if (active) {
      timer ??= Timer.periodic(
        const Duration(milliseconds: 750),
        (_) => poll(),
      );
    } else {
      timer?.cancel();
      timer = null;
    }
    if (active && loading) {
      loadWatch.start();
      deadline ??= Timer(widget.loadTimeout - loadWatch.elapsed, () {
        if (!mounted) return;
        setState(() {
          loading = false;
          error = '學校系統回應逾時。可以再試一次，或直接開啟學校網頁。';
        });
        syncWork();
      });
    } else {
      loadWatch.stop();
      deadline?.cancel();
      deadline = null;
    }
  }

  void sessionChanged() {
    if (session.coordinator.epoch != epoch && mounted) {
      timer?.cancel();
      deadline?.cancel();
      generation++;
      setState(() {
        snapshot = null;
        cached = null;
        entry = null;
        error = '已登出，請重新登入。';
        loading = false;
      });
      syncWork();
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
    timer = null;
    deadline?.cancel();
    deadline = null;
    loadWatch
      ..stop()
      ..reset();
    try {
      await controller?.stopLoading();
    } catch (_) {
      // A platform view may already have been torn down during navigation.
    }
    if (!mounted || current != generation) return;
    controller = null;
    navigated.clear();
    targetReady = false;
    eventLoginRequired = false;
    eventRecoveryAttempted = false;
    interactionRequired = false;
    reconnecting = false;
    schoolPage = false;
    reusedAcademicSession =
        widget.bridge &&
        widget.entryBuilder == null &&
        widget.target?.host == 'acade.niu.edu.tw' &&
        PortalPolicy.academic.allows(widget.target!) &&
        session.hasAcademicSession;
    if (mounted) {
      setState(() {
        error = null;
        loading = true;
        snapshot = null;
        entry = null;
      });
    }
    if (session.isDemo) {
      await showDemo(current);
      return;
    }
    unawaited(restoreCache(current));
    syncWork();
    menuClicked = false;
    try {
      if (widget.bridge && !session.isSignedIn && session.hasLocalAccount) {
        await SchoolReauthorization.restore(session);
        if (!mounted || current != generation || error != null) return;
      }
      final uri = widget.entryBuilder != null
          ? await widget.entryBuilder!(session)
          : widget.bridge
          ? reusedAcademicSession
                ? widget.target!
                : await session.academicEntry()
          : widget.target!;
      if (!mounted || current != generation) return;
      if (!loading) return;
      session.coordinator.requireCurrent(epoch);
      setState(() => entry = uri);
    } catch (_) {
      if (mounted && current == generation) {
        deadline?.cancel();
        setState(() {
          error = '沒有連上校務系統，請重新登入後再試。';
          loading = false;
        });
        syncWork();
      }
    }
  }

  Future<void> restoreCache(int current) async {
    final key = widget.cacheKey;
    if (key == null || cached != null) return;
    final owner = session.account;
    final value = await PortalSnapshotCache.of(session).read(key);
    if (!mounted ||
        current != generation ||
        value == null ||
        session.account != owner) {
      return;
    }
    setState(() => cached = value);
  }

  void saveCache(dynamic value) {
    final key = widget.cacheKey;
    final owner = session.account;
    if (key == null || owner == null || value is! Map<String, dynamic>) return;
    setState(() => cached = CachedSnapshot(DateTime.now(), value));
    unawaited(
      PortalSnapshotCache.of(
        session,
      ).write(key, value, epoch: epoch, owner: owner).catchError((_) {}),
    );
  }

  Future<void> showDemo(int current) async {
    timer?.cancel();
    timer = null;
    deadline?.cancel();
    deadline = null;
    final value = widget.demoSnapshot?.call();
    if (value == null) {
      if (mounted && current == generation) {
        setState(() {
          error = '示範模式沒有提供這個學校頁面。';
          loading = false;
        });
      }
      return;
    }
    // Same JSON round trip as a school page, so parsers see the real shapes.
    final parsed = jsonDecode(jsonEncode(value));
    await widget.onSnapshot?.call(parsed, epoch);
    if (!mounted || current != generation) return;
    setState(() {
      snapshot = parsed;
      snapshotAt = DateTime.now();
      loading = false;
      error = null;
    });
  }

  Future<void> expiredAcademicSession(int current) async {
    if (!mounted ||
        current != generation ||
        session.coordinator.epoch != epoch ||
        reconnecting) {
      return;
    }
    session.invalidateAcademicSession(epoch);
    if (!reusedAcademicSession) {
      setState(() {
        loading = false;
        error = '校務登入已過期，請重新登入。';
        schoolPage = true;
      });
      syncWork();
      return;
    }
    // A reused Cookie can expire independently of SSO. Bridge once, never loop
    // or replay a school form when that bridge also requires user interaction.
    reusedAcademicSession = false;
    reconnecting = true;
    navigated.clear();
    targetReady = false;
    try {
      final uri = await session.academicEntry();
      if (!mounted ||
          current != generation ||
          error != null ||
          !foreground ||
          !routeActive) {
        return;
      }
      session.coordinator.requireCurrent(epoch);
      await controller?.loadUrl(
        urlRequest: URLRequest(url: WebUri(uri.toString())),
      );
    } catch (_) {
      if (mounted && current == generation) {
        setState(() {
          loading = false;
          error = '沒有連上校務系統，請重新登入後再試。';
        });
        syncWork();
      }
    } finally {
      if (current == generation) reconnecting = false;
    }
  }

  Future<void> poll() async {
    if (pollingGeneration == generation ||
        controller == null ||
        reconnecting ||
        !foreground ||
        !routeActive ||
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
        if (!mounted ||
            current != generation ||
            error != null ||
            !foreground ||
            !routeActive) {
          return;
        }
        if (navigation == 'session-expired' && widget.bridge) {
          await expiredAcademicSession(current);
          return;
        }
        if (navigation == 'interaction-required') {
          if (!interactionRequired) {
            setState(() {
              interactionRequired = true;
              loading = false;
              schoolPage = true;
            });
            syncWork();
          }
          return;
        }
        if (navigation == 'login-required') {
          if (!eventRecoveryAttempted && !widget.bridge) {
            eventRecoveryAttempted = true;
            final remembered = RememberSchoolLogin.forSession(session);
            final credentials = await remembered.restore();
            if (!mounted || current != generation || error != null) return;
            if (credentials != null &&
                (session.isSignedIn ||
                    await SchoolReauthorization.restore(session))) {
              if (!mounted || current != generation || error != null) return;
              final restored = await EventLoginService().establish(
                credentials.account,
                credentials.password,
                session,
                epoch,
              );
              if (!mounted || current != generation || error != null) return;
              if (restored) {
                navigated.clear();
                await web.loadUrl(
                  urlRequest: URLRequest(url: WebUri(widget.target.toString())),
                );
                return;
              }
            }
          }
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
            syncWork();
          }
          return;
        }
        if ((eventLoginRequired || interactionRequired) && navigation != null) {
          setState(() {
            eventLoginRequired = false;
            interactionRequired = false;
            loading = true;
            schoolPage = false;
          });
          loadWatch.reset();
          syncWork();
        }
        if (navigation == 'ready') {
          targetReady = true;
          if (widget.extractScript == null) {
            deadline?.cancel();
            timer?.cancel();
            setState(() => loading = false);
            syncWork();
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
      if (widget.menuLabel != null && !menuClicked) {
        final result = await controller!.evaluateJavascript(
          source: academicMenuScript(widget.menuLabel!),
        );
        menuClicked = result == true;
      }
      if (widget.extractScript == null) {
        syncWork();
        return;
      }
      if (widget.target != null && !targetReady) return;
      final value = await web.evaluateJavascript(
        source: academicReadScript(
          extract: widget.extractScript!,
          prepare: widget.prepareScript,
          run: readRun,
        ),
      );
      if (!mounted ||
          current != generation ||
          error != null ||
          !foreground ||
          !routeActive) {
        return;
      }
      if (value is String && value.isNotEmpty && value != 'null') {
        final envelope = jsonDecode(value) as Map<String, dynamic>;
        final identity = await web.evaluateJavascript(
          source: academicDocumentIdentityScript(readRun),
        );
        if (!mounted ||
            current != generation ||
            error != null ||
            !foreground ||
            !routeActive ||
            envelope['signature'] != identity) {
          return;
        }
        final parsed = jsonDecode(envelope['value'] as String);
        if (parsed != null &&
            mounted &&
            current == generation &&
            error == null) {
          session.coordinator.requireCurrent(epoch);
          if (widget.bridge) session.confirmAcademicSession(epoch);
          await widget.onSnapshot?.call(parsed, epoch);
          if (!mounted || current != generation || error != null) return;
          saveCache(parsed);
          setState(() {
            snapshot = parsed;
            snapshotAt = DateTime.now();
            loading = false;
            error = null;
          });
          timer?.cancel();
          deadline?.cancel();
          syncWork();
        }
      }
    } catch (_) {
      // Frames can navigate independently; bounded polling retries their DOM.
    } finally {
      if (pollingGeneration == current) pollingGeneration = null;
    }
  }

  Future<void> loaded(InAppWebViewController web, WebUri? url) async {
    if (!mounted ||
        url == null ||
        web != controller ||
        error != null ||
        !foreground ||
        !routeActive) {
      return;
    }
    final current = generation;
    final uri = Uri.parse(url.toString());
    if (widget.bridge && isAcademicSessionExpired(uri)) {
      await expiredAcademicSession(current);
      return;
    }
    if (widget.extractScript == null &&
        widget.navigationScript == null &&
        mounted) {
      deadline?.cancel();
      setState(() => loading = false);
      syncWork();
    }
    await poll();
  }

  @override
  void dispose() {
    generation++;
    timer?.cancel();
    deadline?.cancel();
    loadWatch.stop();
    WidgetsBinding.instance.removeObserver(this);
    session.removeListener(sessionChanged);
    session.unregisterCleanup(clearWebData);
    controller?.stopLoading();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewGeneration = generation;
    // A fresh snapshot, or the cached one while that loads or fails.
    final shown = snapshot ?? cached?.data;
    final showContent =
        shown != null && !schoolPage && widget.snapshotBuilder != null;
    final nativeCover =
        !schoolPage && widget.extractScript != null && !showContent;
    final stale = snapshot == null && cached != null;
    final blocked = error != null || interactionRequired || eventLoginRequired;
    return Scaffold(
      appBar: NiuAppBar(
        title: widget.title,
        actions: [
          if (widget.extractScript != null && !session.isDemo)
            NiuIconButton(
              tooltip: schoolPage ? '回到 App 檢視' : '查看學校網頁',
              icon: schoolPage
                  ? Icons.dashboard_rounded
                  : Icons.language_rounded,
              onPressed: () => setState(() => schoolPage = !schoolPage),
            ),
          NiuIconButton(
            tooltip: '重新整理',
            icon: NiuIcons.refresh,
            onPressed: loading || reconnecting ? null : start,
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            if (widget.header != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  NiuSpacing.gutter,
                  NiuSpacing.xs,
                  NiuSpacing.gutter,
                  NiuSpacing.md,
                ),
                child: widget.header,
              ),
            if (eventLoginRequired)
              banner(
                NiuBanner(
                  tone: NiuTone.warning,
                  message: '活動報名的登入已過期。重新登入後會回到這個頁面。',
                  actionLabel: '重新登入活動報名',
                  onAction: signIn,
                ),
              ),
            if (interactionRequired)
              banner(
                const NiuBanner(
                  tone: NiuTone.warning,
                  message: '請在學校網頁完成驗證或登入，完成後會自動繼續。',
                ),
              ),
            if (loading && !nativeCover)
              const SizedBox(
                height: 2,
                child: LinearProgressIndicator(
                  minHeight: 2,
                  borderRadius: BorderRadius.zero,
                ),
              ),
            if (error != null && !nativeCover)
              banner(
                NiuBanner(
                  tone: NiuTone.error,
                  message: error!,
                  actionLabel: '重新登入',
                  onAction: signIn,
                ),
              ),
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (entry != null)
                    ExcludeSemantics(
                      excluding: nativeCover || showContent,
                      child: IgnorePointer(
                        ignoring: nativeCover || showContent,
                        child: Offstage(
                          offstage:
                              snapshot != null &&
                              !schoolPage &&
                              widget.snapshotBuilder != null,
                          child: buildWebView(
                            () => InAppWebView(
                              key: ValueKey(generation),
                              initialUrlRequest: URLRequest(
                                url: WebUri(entry.toString()),
                                headers: reusedAcademicSession
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
                              initialSettings: InAppWebViewSettings(
                                javaScriptEnabled: true,
                                sharedCookiesEnabled: true,
                                useShouldOverrideUrlLoading: true,
                                supportMultipleWindows: true,
                                javaScriptCanOpenWindowsAutomatically: true,
                                allowFileAccess: false,
                              ),
                              initialUserScripts: UnmodifiableListView([
                                UserScript(
                                  source: academicNavigationWakeupScript,
                                  injectionTime:
                                      UserScriptInjectionTime.AT_DOCUMENT_START,
                                  forMainFrameOnly: false,
                                ),
                              ]),
                              onWebViewCreated: (web) {
                                if (!mounted || viewGeneration != generation) {
                                  return;
                                }
                                controller = web;
                                final captured = viewGeneration;
                                web.addJavaScriptHandler(
                                  handlerName: 'academicSnapshot',
                                  callback: (arguments) async {
                                    if (!mounted ||
                                        captured != generation ||
                                        session.coordinator.epoch != epoch ||
                                        error != null ||
                                        snapshot != null) {
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
                                    error = '學校網頁載入失敗，檢查網路後再試一次。';
                                    loading = false;
                                  });
                                  syncWork();
                                }
                              },
                              onReceivedHttpError:
                                  (web, request, response) async {
                                    if (!mounted ||
                                        web != controller ||
                                        request.isForMainFrame != true) {
                                      return;
                                    }
                                    if (widget.bridge &&
                                        [
                                          401,
                                          403,
                                        ].contains(response.statusCode)) {
                                      await expiredAcademicSession(
                                        viewGeneration,
                                      );
                                      return;
                                    }
                                    setState(() {
                                      error = '學校系統暫時沒有回應，稍後再試。';
                                      loading = false;
                                    });
                                    syncWork();
                                  },
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (showContent)
                    Positioned.fill(
                      child: ColoredBox(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (widget.cacheKey != null)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  NiuSpacing.gutter,
                                  NiuSpacing.xs,
                                  NiuSpacing.gutter,
                                  NiuSpacing.xs,
                                ),
                                child: NiuSyncStatus(
                                  updatedAt: stale
                                      ? cached!.updatedAt
                                      : snapshotAt,
                                  refreshing: stale && !blocked,
                                  failed: stale && blocked,
                                  offline: stale && session.isOffline,
                                  onRetry: stale && error != null
                                      ? start
                                      : null,
                                ),
                              ),
                            Expanded(
                              child: widget.snapshotBuilder!(context, shown),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (nativeCover)
                    Positioned.fill(
                      child: ColoredBox(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        child: Center(
                          child: SingleChildScrollView(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (interactionRequired || eventLoginRequired)
                                  NiuEmpty(
                                    icon: NiuIcons.lock,
                                    tone: NiuTone.accent,
                                    title: '需要在學校網頁完成驗證',
                                    message: '開啟學校網頁完成登入或驗證後，資料會自動讀取。',
                                    action: FilledButton(
                                      onPressed: entry == null
                                          ? null
                                          : () => setState(
                                              () => schoolPage = true,
                                            ),
                                      child: const Text('開啟學校網頁'),
                                    ),
                                  )
                                else if (error == null) ...[
                                  const NiuLoading(message: '正在向學校系統讀取資料'),
                                  TextButton(
                                    onPressed: entry == null
                                        ? null
                                        : () =>
                                              setState(() => schoolPage = true),
                                    child: const Text('開啟學校網頁'),
                                  ),
                                ] else
                                  NiuError(
                                    title: '無法取得資料',
                                    message: error!,
                                    onRetry: start,
                                    secondaryAction: Wrap(
                                      alignment: WrapAlignment.center,
                                      children: [
                                        TextButton(
                                          onPressed: signIn,
                                          child: const Text('重新登入'),
                                        ),
                                        TextButton(
                                          onPressed: entry == null
                                              ? null
                                              : () => setState(
                                                  () => schoolPage = true,
                                                ),
                                          child: const Text('開啟學校網頁'),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (entry == null &&
                      error == null &&
                      snapshot == null &&
                      !nativeCover)
                    const Center(child: NiuLoading(message: '正在連線')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildWebView(Widget Function() create) =>
      widget.webViewBuilder?.call(create) ?? create();

  Widget banner(Widget child) => Flexible(
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        NiuSpacing.gutter,
        NiuSpacing.xs,
        NiuSpacing.gutter,
        NiuSpacing.md,
      ),
      child: child,
    ),
  );

  Future<void> signIn() async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => LoginScreen(session: session)),
    );
    if (ok == true && mounted) start();
  }
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
