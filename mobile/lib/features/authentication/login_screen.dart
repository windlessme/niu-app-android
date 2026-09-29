import 'dart:async';
import 'dart:collection';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../core/session/campus_session.dart';
import '../../core/web/portal_policy.dart';
import '../../shared/shared.dart';
import '../moodle/moodle_login_service.dart';
import '../events/event_login_service.dart';
import 'school_login_capture.dart';
import 'remember_school_login.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.session, this.onSignedIn});
  final CampusSession? session;
  final VoidCallback? onSignedIn;
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  InAppWebViewController? controller;
  Timer? timer;
  late final session = widget.session ?? CampusSession.instance;
  late final epoch = session.coordinator.epoch;
  late final remembered = RememberSchoolLogin.forSession(session);
  SubmittedSchoolCredentials? prefillCredentials;
  bool preferenceReady = false;
  int documentGeneration = 0;
  int prefillAttempts = 0;
  bool prefilling = false;
  bool prefillDone = false;
  String? error;
  String rejectedToken = '';
  bool checking = false;
  bool complete = false;
  bool connectingServices = false;
  double progress = 0;
  SubmittedSchoolCredentials? submittedCredentials;
  final captureCapability = List.generate(
    32,
    (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();

  @override
  void initState() {
    super.initState();
    session.registerCleanup(clearWebData);
    remembered.setEnabled(true);
    restoreRemembered();
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      prefill();
      checkToken();
    });
  }

  Future<void> restoreRemembered() async {
    try {
      final saved = await remembered.restore();
      session.coordinator.requireCurrent(epoch);
      if (!mounted) return;
      setState(() {
        prefillCredentials = saved;
      });
    } catch (_) {
      if (mounted) setState(() => error = '無法讀取已記住的帳密，請手動輸入。');
    } finally {
      if (mounted) setState(() => preferenceReady = true);
    }
    await prefill();
  }

  Future<void> prefill() async {
    final saved = prefillCredentials;
    if (!mounted ||
        controller == null ||
        saved == null ||
        !remembered.enabled ||
        prefilling ||
        prefillDone ||
        prefillAttempts >= 20) {
      return;
    }
    final document = documentGeneration;
    final consent = remembered.revision;
    prefilling = true;
    try {
      final page = await controller!.getUrl();
      session.coordinator.requireCurrent(epoch);
      if (!mounted ||
          document != documentGeneration ||
          consent != remembered.revision ||
          !remembered.enabled ||
          !isSchoolLoginPage(Uri.tryParse('$page'))) {
        return;
      }
      prefillAttempts++;
      final result = await controller!.evaluateJavascript(
        source: schoolLoginPrefillScript(saved),
      );
      if (document == documentGeneration && result != 'waiting') {
        prefillDone = true;
      }
    } catch (_) {
      // Navigation can destroy the context. Polling is bounded per document.
    } finally {
      prefilling = false;
    }
  }

  Future<void> clearWebData() async {
    submittedCredentials = null;
    prefillCredentials = null;
    timer?.cancel();
    await controller?.stopLoading();
    await controller?.evaluateJavascript(
      source: 'sessionStorage.clear(); localStorage.clear();',
    );
  }

  Future<void> checkToken() async {
    if (controller == null ||
        checking ||
        complete ||
        !mounted ||
        !preferenceReady) {
      return;
    }
    checking = true;
    try {
      final uri = await controller!.getUrl();
      if (!isSchoolLoginOrigin(Uri.tryParse('$uri'))) return;
      final raw = await controller!.evaluateJavascript(
        source: '''
        sessionStorage.getItem('niu_sso_token') || ''
      ''',
      );
      if (raw is! String) return;
      final token = raw;
      if (token.isEmpty || token == rejectedToken) return;
      if (!mounted) return;
      session.coordinator.requireCurrent(epoch);
      // acceptToken notifies route listeners synchronously. They may dispose
      // this view, so consume credentials before awaiting identity verification.
      // The local handoff may finish after disposal; epoch/account guards still
      // prevent a logout or account change from establishing a Moodle session.
      final credentials = submittedCredentials;
      final consentRevision = remembered.revision;
      submittedCredentials = null;
      try {
        await session.acceptToken(token, credentials?.account, epoch: epoch);
      } catch (_) {
        submittedCredentials = null;
        rejectedToken = token;
        if (mounted) setState(() => error = '無法驗證登入憑證，請重新載入校方頁面後再試。切換帳號前請先登出。');
        return;
      }
      session.coordinator.requireCurrent(epoch);
      if (credentials != null) {
        try {
          await remembered.saveVerified(
            credentials,
            epoch: epoch,
            consentRevision: consentRevision,
          );
        } catch (_) {
          if (mounted) setState(() => error = '已登入，但無法安全記住帳密。');
        }
        if (mounted) setState(() => connectingServices = true);
        // Independent services can connect concurrently after SSO verification.
        // Each failure remains local; neither invalidates the verified SSO login.
        await Future.wait<void>([
          () async {
            try {
              await MoodleLoginService(session).establish(
                account: credentials.account,
                password: credentials.password,
                epoch: epoch,
              );
            } catch (_) {
              // The visible Moodle flow handles any required interaction.
            }
          }(),
          () async {
            try {
              await EventLoginService().establish(
                credentials.account,
                credentials.password,
                session,
                epoch,
              );
            } catch (_) {
              // The event page exposes reconnect if needed.
            }
          }(),
        ]);
      }
      session.coordinator.requireCurrent(epoch);
      if (!mounted) return;
      setState(() => connectingServices = false);
      complete = true;
      timer?.cancel();
      if (widget.onSignedIn != null) {
        widget.onSignedIn!();
      } else if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop(true);
      } else {
        setState(() {});
      }
    } catch (_) {
      // Navigation can briefly destroy the JS context; check the next page.
    } finally {
      checking = false;
      if (mounted && connectingServices) {
        setState(() => connectingServices = false);
      }
    }
  }

  @override
  void dispose() {
    submittedCredentials = null;
    prefillCredentials = null;
    session.unregisterCleanup(clearWebData);
    timer?.cancel();
    controller?.stopLoading();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: IosPageHeader(
      title: '校務登入',
      actions: [
        CircleIconButton(
          label: '重新載入',
          icon: Icons.refresh,
          onPressed: connectingServices
              ? null
              : () {
                  submittedCredentials = null;
                  rejectedToken = '';
                  setState(() => error = null);
                  controller?.loadUrl(
                    urlRequest: URLRequest(
                      url: WebUri('https://ccsys1.niu.edu.tw/SSO/login'),
                    ),
                  );
                },
        ),
      ],
    ),
    body: SafeArea(
      top: false,
      child: complete
          ? Center(child: Text('已登入：${session.displayName}'))
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  child: Text(
                    '登入成功後會在此裝置加密記住帳密，下次自動填入。可於設定清除。',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                if (connectingServices)
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('校務登入成功，正在連接 M 園區與活動系統…'),
                  ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      error!,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (progress < 1) LinearProgressIndicator(value: progress),
                Expanded(
                  child: InAppWebView(
                    initialUserScripts: UnmodifiableListView([
                      UserScript(
                        source: schoolLoginCaptureScript(captureCapability),
                        injectionTime:
                            UserScriptInjectionTime.AT_DOCUMENT_START,
                        forMainFrameOnly: true,
                      ),
                    ]),
                    initialUrlRequest: URLRequest(
                      url: WebUri('https://ccsys1.niu.edu.tw/SSO/login'),
                    ),
                    initialSettings: InAppWebViewSettings(
                      javaScriptEnabled: true,
                      useShouldOverrideUrlLoading: true,
                      allowFileAccess: false,
                    ),
                    onWebViewCreated: (value) {
                      controller = value;
                      value.addJavaScriptHandler(
                        handlerName: 'schoolLoginSubmitted',
                        callback: (arguments) async {
                          if (!mounted || complete || arguments.length != 1) {
                            return;
                          }
                          final page = await value.getUrl();
                          if (!mounted || complete) return;
                          session.coordinator.requireCurrent(epoch);
                          final captured =
                              SubmittedSchoolCredentials.fromMessage(
                                arguments.single,
                                page: Uri.tryParse('$page'),
                                capability: captureCapability,
                              );
                          if (captured != null) {
                            final previousToken =
                                (arguments.single as Map)['previousToken'];
                            if (previousToken is String &&
                                previousToken.isNotEmpty) {
                              rejectedToken = previousToken;
                            }
                            submittedCredentials = captured;
                          }
                        },
                      );
                    },
                    onProgressChanged: (_, value) {
                      if (mounted) setState(() => progress = value / 100);
                    },
                    onLoadStart: (_, _) {
                      documentGeneration++;
                      prefillAttempts = 0;
                      prefillDone = false;
                    },
                    onLoadStop: (_, _) => prefill(),
                    shouldOverrideUrlLoading: (_, action) async {
                      if (action.isForMainFrame == false) {
                        return NavigationActionPolicy.ALLOW;
                      }
                      final uri = Uri.tryParse(
                        action.request.url?.toString() ?? '',
                      );
                      return uri != null && PortalPolicy.academic.allows(uri)
                          ? NavigationActionPolicy.ALLOW
                          : NavigationActionPolicy.CANCEL;
                    },
                    onReceivedError: (_, request, failure) {
                      if (request.isForMainFrame == true && mounted) {
                        setState(() => error = '校方登入頁載入失敗，請檢查網路後按重新載入。');
                      }
                    },
                  ),
                ),
              ],
            ),
    ),
  );
}
