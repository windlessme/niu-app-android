import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../core/analytics/app_analytics.dart';
import '../../shared/shared.dart';
import 'moodle_demo.dart';
import 'moodle_question_demo.dart';
import 'moodle_question_widgets.dart';
import 'moodle_questions.dart';
import 'moodle_repository.dart';

/// Reads and drives one activity page; the school WebView, or a stand-in.
abstract class MoodleQuestionDriver {
  /// The page as JSON, or null while it cannot be read.
  Future<String?> snapshot();

  /// 'invoked', 'changed' or 'invalid' (see [moodleQuestionPerform]).
  Future<String?> perform(
    String revision,
    String actionId,
    Map<String, List<String>> answers,
  );

  /// 'staged', 'changed' or 'invalid' (see [moodleQuestionStage]).
  Future<String?> stage(String revision, Map<String, List<String>> answers);
  Future<void> focus(String questionId);
}

class _WebQuestionDriver implements MoodleQuestionDriver {
  _WebQuestionDriver(this.web);
  final InAppWebViewController web;

  /// Writing drag-and-drop words waits for Moodle's animations, so these
  /// resolve a promise, as WebKit's callAsyncJavaScript does on iOS.
  Future<String?> _call(String body, Map<String, dynamic> arguments) async {
    final result = await web.callAsyncJavaScript(
      functionBody: body,
      arguments: arguments,
    );
    if (result?.error case final error?) throw StateError(error);
    final value = result?.value;
    return value is String ? value : null;
  }

  @override
  Future<String?> snapshot() async {
    if (await web.isLoading()) return null;
    final value = await web.evaluateJavascript(source: moodleQuestionSnapshot);
    return value is String ? value : null;
  }

  @override
  Future<String?> perform(
    String revision,
    String actionId,
    Map<String, List<String>> answers,
  ) => _call(moodleQuestionPerform, {
    'revision': revision,
    'actionID': actionId,
    'answers': answers,
  });
  @override
  Future<String?> stage(String revision, Map<String, List<String>> answers) =>
      _call(moodleQuestionStage, {'revision': revision, 'answers': answers});
  @override
  Future<void> focus(String questionId) =>
      web.evaluateJavascript(source: moodleQuestionFocus(questionId));
}

/// One question activity (測驗、即時問答、選擇、回饋、問卷、調查), as on iOS:
/// the signed-in school page stays under a native view that is read from its
/// DOM every second. Answers are written into the school's own inputs and its
/// own buttons are pressed, so its validation, timers and tokens all apply.
/// Anything the reader cannot show faithfully sends the student to the page.
class MoodleQuestionScreen extends StatefulWidget {
  const MoodleQuestionScreen({
    super.key,
    required this.repository,
    required this.module,
    this.driver,
  });
  final MoodleRepository repository;
  final Json module;

  /// Test seam; the review demo gets a simulated quiz.
  final MoodleQuestionDriver? driver;
  @override
  State<MoodleQuestionScreen> createState() => _MoodleQuestionScreenState();
}

class _MoodleQuestionScreenState extends State<MoodleQuestionScreen>
    with WidgetsBindingObserver {
  late final kind = MoodleQuestionKind.of(widget.module);
  late final target = MoodleQuestionKind.entry(widget.module);
  late final Future<Uri> entry = _entry();
  InAppWebViewController? web;
  late MoodleQuestionDriver? driver =
      widget.driver ??
      (widget.repository is DemoMoodleRepository ? DemoQuestionDriver() : null);

  /// No school page behind the view (demo and tests).
  late final bool simulated =
      widget.driver != null || widget.repository is DemoMoodleRepository;
  Timer? timer;
  MoodleQuestionPage? page;
  Map<String, List<String>> answers = {};
  final texts = <String, TextEditingController>{};
  final questionKeys = <String, GlobalKey>{};
  String? error;
  bool loading = true, showWeb = false, performing = false, reading = false;
  bool foreground = true, syncingPage = false, needsAnswerSync = false;
  int failures = 0;
  String? submittedRevision;
  DateTime? submissionStarted;

  /// Bumped on reload and dispose so late draft writes are dropped.
  int generation = 0;
  Future<void>? draftTask;
  bool draftPending = false;

  /// A school dialog is open; reading the page would block behind it.
  bool dialog = false;

  Future<Uri> _entry() async {
    final uri = target;
    if (uri == null) throw StateError('目前無法開啟此活動。');
    try {
      return await widget.repository.webUri(uri);
    } catch (_) {
      // Auto-login keys are rate limited; existing cookies may still work.
      return uri;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    timer = Timer.periodic(const Duration(seconds: 1), (_) => read());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
  }

  @override
  void dispose() {
    generation++;
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    for (final c in texts.values) {
      c.dispose();
    }
    super.dispose();
  }

  bool get current {
    if (!mounted) return false;
    try {
      widget.repository.requireCurrent();
      return true;
    } catch (_) {
      return false;
    }
  }

  static bool allowed(Uri u) =>
      u.scheme == 'https' &&
      (!u.hasPort || u.port == 443) &&
      u.userInfo.isEmpty &&
      const {
        'euni.niu.edu.tw',
        'sso.niu.edu.tw',
        'ccsys.niu.edu.tw',
        'ccsys1.niu.edu.tw',
      }.contains(u.host);

  Future<void> read() async {
    final source = driver;
    if (source == null || reading || dialog || showWeb || !foreground) {
      return;
    }
    if (!current) {
      timer?.cancel();
      setState(() {
        page = null;
        error = '登入狀態已變更，請返回課程後重新開啟。';
      });
      return;
    }
    reading = true;
    try {
      final raw = await source.snapshot();
      if (!current || raw == null) return;
      accept(MoodleQuestionPage.fromJson(jsonDecode(raw) as Map));
      failures = 0;
    } catch (_) {
      if (++failures >= 3 && mounted && page == null) {
        setState(() => error = '暫時無法讀取題目，請重試或查看校方頁面。');
      }
    } finally {
      reading = false;
    }
    final started = submissionStarted;
    if (started != null &&
        DateTime.now().difference(started) > const Duration(seconds: 15) &&
        mounted) {
      // Stay locked until a different school page arrives.
      setState(() => error = '尚未取得可確認的校方回應。請查看校方頁面確認作答紀錄，避免重複送出。');
    }
  }

  static bool same(Map<String, List<String>> a, Map<String, List<String>> b) =>
      a.length == b.length &&
      a.entries.every(
        (e) =>
            b[e.key] != null &&
            b[e.key]!.join('\u0000') == e.value.join('\u0000'),
      );

  void accept(MoodleQuestionPage next) {
    final previous = page;
    setState(() {
      loading = false;
      if (previous?.revision != next.revision || needsAnswerSync) {
        final edited =
            previous != null &&
            !performing &&
            !needsAnswerSync &&
            !same(answers, previous.values);
        error = edited ? '校方題目或選項已更新，請重新確認答案。' : null;
        answers = next.values;
        for (final field in next.fields) {
          if (field.kind == 'text' || field.kind == 'longText') {
            text(field).text = field.values.firstOrNull ?? '';
          }
        }
        needsAnswerSync = false;
        syncingPage = false;
      }
      if (submittedRevision != null && submittedRevision != next.revision) {
        performing = false;
        submittedRevision = null;
        submissionStarted = null;
      }
      page = next;
    });
  }

  TextEditingController text(MoodleQuestionField field) =>
      texts.putIfAbsent(field.id, TextEditingController.new);

  bool get ready =>
      page != null && !performing && !syncingPage && current && driver != null;

  void answer(
    MoodleQuestionField field,
    List<String> Function(List<String> now) change,
  ) {
    setState(
      () => answers[field.id] = change(answers[field.id] ?? field.values),
    );
    draftChanged();
  }

  /// Timed activities can be submitted by the school page when time runs
  /// out, so every native change is written to its form right away.
  void draftChanged() {
    final shown = page;
    if (shown == null ||
        shown.timer == null ||
        shown.webReason != null ||
        performing ||
        syncingPage ||
        showWeb ||
        same(answers, shown.values)) {
      return;
    }
    draftPending = true;
    draftTask ??= writeDrafts().whenComplete(() => draftTask = null);
  }

  Future<void> writeDrafts() async {
    final run = generation;
    while (draftPending && mounted && run == generation && !performing) {
      final shown = page;
      if (shown == null || shown.webReason != null || driver == null) return;
      draftPending = false;
      String? result;
      try {
        result = await driver!.stage(shown.revision, answers);
      } catch (_) {}
      if (!mounted || run != generation) return;
      if (result != 'staged') {
        setState(() => error = '答案未能即時寫入校方頁面，請改用校方頁面確認作答。');
        return;
      }
    }
  }

  /// Quiz steps follow Moodle's own confirmations (start preflight, submit
  /// dialog), so only other activities get the extra native confirmation.
  Future<void> perform(MoodleQuestionAction action) async {
    final shown = page;
    if (!ready || shown == null || shown.webReason != null) return;
    FocusScope.of(context).unfocus();
    if (!action.isNavigation && !shown.isQuizFlow) {
      final ok =
          await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('確認操作'),
              content: Text(
                '將在 M 園區執行「${action.label}」。開始或送出作答可能影響測驗次數與成績，請確認答案後繼續。',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('確定'),
                ),
              ],
            ),
          ) ??
          false;
      // The page may have changed while the dialog was open.
      if (!ok || !ready || page?.revision != shown.revision) return;
    }
    final values = {for (final id in action.fieldIds) id: ?answers[id]};
    final draft = draftTask;
    setState(() {
      performing = true;
      error = null;
      submittedRevision = shown.revision;
      submissionStarted = DateTime.now();
    });
    void unlock(String message) => setState(() {
      performing = false;
      submittedRevision = null;
      submissionStarted = null;
      error = message;
    });
    // A timed-draft write must finish before the school control is clicked.
    await draft;
    if (!mounted) return;
    if (page?.revision != shown.revision) {
      unlock('題目或操作已變更，請重新確認目前內容。');
      return;
    }
    try {
      final result = await driver!.perform(shown.revision, action.id, values);
      if (!mounted) return;
      if (result != 'invoked') {
        unlock(
          result == 'invalid'
              ? '請確認必填欄位、字數與輸入格式，且同一個拖放字詞沒有重複使用。'
              : '題目或操作已變更，請重新確認目前內容。',
        );
      } else if (!action.isNavigation) {
        AppAnalytics.instance.event('moodle_question', {
          'kind': kind?.name ?? 'unknown',
        });
      }
    } catch (_) {
      // A navigation can end the script after a successful click; never
      // retry something that may already have been submitted.
      if (mounted) {
        setState(() => error = '無法確認操作結果，請查看校方頁面確認，避免重複送出。');
      }
    }
  }

  /// An answer-card bubble: this page scrolls to the question; another page
  /// goes through Moodle's own handler, which saves this page first.
  void jump(MoodleQuizNavItem item, MoodleQuestionPage shown) {
    if (item.current) {
      final question = shown.questions
          ?.where((q) => q.number == item.number)
          .firstOrNull;
      final target = questionKeys[question?.id]?.currentContext;
      if (target != null) {
        Scrollable.ensureVisible(
          target,
          duration: const Duration(milliseconds: 250),
        );
        return;
      }
    }
    perform(
      MoodleQuestionAction.jump(item.id, item.number, [
        for (final f in shown.fields) f.id,
      ]),
    );
  }

  /// Shows the school page with what was entered here already written in.
  Future<void> openSchool() async {
    final shown = page;
    if (simulated) return;
    if (shown == null || shown.webReason != null || performing || !ready) {
      setState(() => showWeb = true);
      return;
    }
    setState(() => syncingPage = true);
    try {
      final result = await driver!.stage(shown.revision, answers);
      if (!mounted) return;
      setState(() {
        syncingPage = false;
        if (result == 'staged') {
          showWeb = true;
        } else {
          error = '無法保留目前輸入，請先確認題目與字數後再切換。';
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          syncingPage = false;
          error = '暫時無法切換介面，目前輸入仍保留，請稍後再試。';
        });
      }
    }
  }

  void returnToApp() => setState(() {
    showWeb = false;
    needsAnswerSync = true;
  });

  Future<void> reviewQuestion(String id) async {
    if (!ready || simulated) return;
    setState(() => showWeb = true);
    try {
      await driver!.focus(id);
    } catch (_) {
      if (mounted) setState(() => error = '校方頁面已更新，請在頁面中選擇要複習的題目。');
    }
  }

  Future<void> reload() async {
    final ok =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('重新開啟活動？'),
            content: const Text('尚未送出的輸入將清除。若剛執行過送出，請先查看校方頁面確認紀錄。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('重新開啟'),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok || !mounted) return;
    generation++;
    draftPending = false;
    draftTask = null;
    setState(() {
      page = null;
      answers = {};
      error = null;
      loading = true;
      performing = false;
      submittedRevision = null;
      submissionStarted = null;
      showWeb = false;
    });
    if (simulated) {
      if (driver case final DemoQuestionDriver demo) demo.restart();
      return;
    }
    final uri = await entry;
    await web?.loadUrl(urlRequest: URLRequest(url: WebUri('$uri')));
  }

  /// School alerts, confirms and prompts stay interactive, as on iOS.
  Future<String?> schoolDialog(String message, {String? input}) async {
    dialog = true;
    final field = input == null ? null : TextEditingController(text: input);
    try {
      return await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('M 園區'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(message),
              if (field != null) TextField(controller: field, autofocus: true),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, field?.text ?? ''),
              child: const Text('確定'),
            ),
          ],
        ),
      );
    } finally {
      dialog = false;
      field?.dispose();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: NiuAppBar(
      title: kind?.title ?? '問答',
      actions: [
        if (!simulated)
          NiuIconButton(
            tooltip: showWeb ? '返回 App 檢視' : '查看校方頁面',
            icon: showWeb ? Icons.dashboard_rounded : Icons.language_rounded,
            onPressed: syncingPage
                ? null
                : showWeb
                ? returnToApp
                : openSchool,
          ),
        NiuIconButton(
          tooltip: '重新開啟活動',
          icon: NiuIcons.refresh,
          onPressed: reload,
        ),
      ],
    ),
    body: SafeArea(
      top: false,
      child: simulated
          ? Material(
              color: NiuColors.of(context).canvas,
              child: native(context),
            )
          : FutureBuilder<Uri>(
              future: entry,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(
                    child: NiuError(
                      title: '目前無法開啟此活動',
                      message: '可能尚未開放或不符合存取條件。',
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: NiuLoading(message: '正在連線'));
                }
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    ExcludeSemantics(
                      excluding: !showWeb,
                      child: IgnorePointer(
                        ignoring: !showWeb,
                        child: InAppWebView(
                          initialUrlRequest: URLRequest(
                            url: WebUri('${snapshot.data}'),
                          ),
                          initialSettings: InAppWebViewSettings(
                            useShouldOverrideUrlLoading: true,
                            javaScriptEnabled: true,
                            sharedCookiesEnabled: true,
                            allowFileAccess: false,
                            supportMultipleWindows: false,
                          ),
                          onWebViewCreated: (controller) {
                            web = controller;
                            driver = _WebQuestionDriver(controller);
                          },
                          shouldOverrideUrlLoading: (_, action) async =>
                              action.request.url != null &&
                                  allowed(Uri.parse('${action.request.url}'))
                              ? NavigationActionPolicy.ALLOW
                              : NavigationActionPolicy.CANCEL,
                          onJsAlert: (_, request) async {
                            await schoolDialog(request.message ?? '');
                            return JsAlertResponse(
                              handledByClient: true,
                              action: JsAlertResponseAction.CONFIRM,
                            );
                          },
                          onJsConfirm: (_, request) async {
                            final ok = await schoolDialog(
                              request.message ?? '',
                            );
                            return JsConfirmResponse(
                              handledByClient: true,
                              action: ok != null
                                  ? JsConfirmResponseAction.CONFIRM
                                  : JsConfirmResponseAction.CANCEL,
                            );
                          },
                          onJsPrompt: (_, request) async {
                            final value = await schoolDialog(
                              request.message ?? '',
                              input: request.defaultValue ?? '',
                            );
                            return JsPromptResponse(
                              handledByClient: true,
                              value: value,
                              action: value != null
                                  ? JsPromptResponseAction.CONFIRM
                                  : JsPromptResponseAction.CANCEL,
                            );
                          },
                          onReceivedError: (_, request, _) {
                            if (request.isForMainFrame == true && mounted) {
                              setState(() => error = 'M 園區內容載入失敗，請檢查網路後重新開啟。');
                            }
                          },
                        ),
                      ),
                    ),
                    if (!showWeb)
                      Material(
                        color: NiuColors.of(context).canvas,
                        child: native(context),
                      ),
                  ],
                );
              },
            ),
    ),
  );

  Widget native(BuildContext context) {
    final shown = page;
    if (shown == null) {
      if (error case final message?) {
        return Center(
          child: NiuError(title: '問答載入失敗', message: message, onRetry: reload),
        );
      }
      return const Center(child: NiuLoading(message: '正在讀取題目'));
    }
    final quiz = shown.isQuizFlow;
    // The summary lists every question itself; its bar keeps only the timer.
    final cardBar =
        quiz &&
        (shown.stage == 'attempt' && shown.navigation.isNotEmpty ||
            (shown.stage == 'attempt' || shown.stage == 'summary') &&
                shown.timerSeconds != null);
    return Column(
      children: [
        if (cardBar) answerCardBar(context, shown),
        Expanded(
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(
              NiuSpacing.gutter,
              NiuSpacing.md,
              NiuSpacing.gutter,
              NiuSpacing.huge,
            ),
            children: [
              if (error case final message?) ...[
                NiuBanner(tone: NiuTone.warning, message: message),
                const SizedBox(height: NiuSpacing.lg),
              ],
              ...quiz
                  ? switch (shown.stage) {
                      'overview' => overview(context, shown),
                      'attempt' => attempt(context, shown),
                      'summary' => summary(context, shown),
                      'confirm' => confirmation(context, shown),
                      _ => review(context, shown),
                    }
                  : generic(context, shown),
            ],
          ),
        ),
        if (quiz) ?actionBar(context, shown),
      ],
    );
  }

  Widget heading(BuildContext context, String text) => Text(
    text,
    style: Theme.of(
      context,
    ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
  );

  List<Widget> overview(BuildContext context, MoodleQuestionPage shown) {
    final theme = Theme.of(context);
    final reviews = [
      for (final a in shown.actions)
        if (a.role == 'review') a,
    ];
    return [
      heading(context, plain(widget.module['name'])),
      if (shown.text.isNotEmpty) ...[
        const SizedBox(height: NiuSpacing.md),
        SelectableText(
          shown.text,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: NiuColors.of(context).inkSecondary,
          ),
        ),
      ],
      if (shown.result case final result?) ...[
        const SizedBox(height: NiuSpacing.lg),
        QuestionResultView(result: result),
      ],
      if (reviews.length > 1) ...[
        const SizedBox(height: NiuSpacing.lg),
        NiuCard(
          padding: const EdgeInsets.symmetric(vertical: NiuSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  NiuSpacing.lg,
                  NiuSpacing.sm,
                  NiuSpacing.lg,
                  NiuSpacing.xs,
                ),
                child: Text('複習作答', style: theme.textTheme.titleSmall),
              ),
              for (final action in reviews)
                ListTile(
                  title: Text(action.label.replaceAll('：', ' ')),
                  trailing: const Icon(NiuIcons.forward),
                  enabled: ready,
                  onTap: () => perform(action),
                ),
            ],
          ),
        ),
      ],
      ...otherActions(shown),
    ];
  }

  List<Widget> attempt(BuildContext context, MoodleQuestionPage shown) {
    final questions = shown.questions ?? const <MoodleQuizQuestion>[];
    final ids = {for (final q in questions) q.id};
    return [
      for (final question in questions) ...[
        questionCard(context, question, [
          for (final f in shown.fields)
            if (f.questionId == question.id) f,
        ]),
        const SizedBox(height: NiuSpacing.lg),
      ],
      // Controls outside a quiz question (rare) still need to be answerable.
      for (final field in shown.fields)
        if (!ids.contains(field.questionId)) ...[
          NiuCard(child: fieldView(field)),
          const SizedBox(height: NiuSpacing.lg),
        ],
      if (shown.text.isNotEmpty)
        SelectableText(
          shown.text,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ...otherActions(shown),
    ];
  }

  Widget questionCard(
    BuildContext context,
    MoodleQuizQuestion question,
    List<MoodleQuestionField> fields,
  ) {
    final theme = Theme.of(context);
    final colors = NiuColors.of(context);
    final done = fields.isNotEmpty && fields.every(answered);
    return NiuCard(
      key: questionKeys.putIfAbsent(question.id, GlobalKey.new),
      padding: const EdgeInsets.all(NiuSpacing.lg + 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '第 ${question.number} 題',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: colors.inkSecondary,
                    ),
                  ),
                ),
                if (fields.isNotEmpty) ...[
                  AnswerMark(filled: done, width: 18, height: 10),
                  const SizedBox(width: 6),
                  Text(done ? '已作答' : '未作答', style: theme.textTheme.bodySmall),
                ],
              ],
            ),
          ),
          if (question.text.isNotEmpty) ...[
            const SizedBox(height: NiuSpacing.md),
            SelectableText(
              question.text,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          for (final field in fields) ...[
            const SizedBox(height: NiuSpacing.lg),
            fieldView(field),
          ],
        ],
      ),
    );
  }

  Widget fieldView(MoodleQuestionField field) => QuestionFieldView(
    field: field,
    values: answers[field.id] ?? field.values,
    enabled: !field.disabled && ready,
    onChanged: (change) => answer(field, change),
    controller: text(field),
  );

  List<Widget> summary(BuildContext context, MoodleQuestionPage shown) {
    final theme = Theme.of(context);
    final colors = NiuColors.of(context);
    final items = shown.navigation;
    final open = items
        .where((i) => i.state == 'unanswered' || i.state == 'invalid')
        .length;
    return [
      heading(context, '交卷前檢查'),
      const SizedBox(height: NiuSpacing.sm),
      Text(
        items.isEmpty
            ? '確認答案後即可交卷。'
            : open == 0
            ? '全部 ${items.length} 題都已作答。'
            : '還有 $open 題未作答。點題號可回到該題。',
        style: theme.textTheme.bodyLarge?.copyWith(
          color: open == 0 ? colors.inkSecondary : colors.warning,
        ),
      ),
      if (items.isNotEmpty) ...[
        const SizedBox(height: NiuSpacing.lg),
        NiuCard(
          padding: const EdgeInsets.symmetric(vertical: NiuSpacing.xs),
          child: Column(
            children: [
              for (final (i, item) in items.indexed) ...[
                if (i > 0)
                  Divider(height: 1, indent: 64, color: colors.hairline),
                Semantics(
                  label: '第 ${item.number} 題，${item.status}',
                  button: true,
                  excludeSemantics: true,
                  child: ListTile(
                    enabled: ready,
                    leading: AnswerBubble(
                      number: item.number,
                      filled: item.state == 'answered',
                      invalid: item.state == 'invalid',
                    ),
                    title: Text(
                      item.status.isNotEmpty
                          ? item.status
                          : item.state == 'answered'
                          ? '已作答'
                          : '未作答',
                      style: TextStyle(
                        color: item.state == 'answered'
                            ? colors.inkSecondary
                            : null,
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (item.flagged)
                          Icon(Icons.flag_rounded, color: colors.warning),
                        const Icon(NiuIcons.forward),
                      ],
                    ),
                    onTap: () => perform(
                      MoodleQuestionAction.jump(item.id, item.number, const []),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
      if (shown.text.isNotEmpty) ...[
        const SizedBox(height: NiuSpacing.lg),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(NiuIcons.time, size: 18, color: colors.inkSecondary),
            const SizedBox(width: NiuSpacing.sm),
            Expanded(child: Text(shown.text, style: theme.textTheme.bodySmall)),
          ],
        ),
      ],
      ...otherActions(shown),
    ];
  }

  List<Widget> confirmation(BuildContext context, MoodleQuestionPage shown) {
    final theme = Theme.of(context);
    final lines = [
      for (final l in shown.text.split('\n'))
        if (l != shown.title) l,
    ];
    bool warning(String l) => l.contains('尚未作答') || l.contains('未回答');
    return [
      const SizedBox(height: NiuSpacing.xxl),
      heading(context, shown.title.isEmpty ? '確認' : shown.title),
      for (final line in lines)
        if (!warning(line)) ...[
          const SizedBox(height: NiuSpacing.md),
          Text(line, style: theme.textTheme.bodyLarge),
        ],
      for (final line in lines)
        if (warning(line)) ...[
          const SizedBox(height: NiuSpacing.md),
          NiuBanner(tone: NiuTone.warning, message: line),
        ],
      if (shown.actions.any((a) => a.role == 'confirm')) ...[
        const SizedBox(height: NiuSpacing.lg),
        Text('這是校方的確認步驟，按下後才會正式送出。', style: theme.textTheme.bodySmall),
      ],
    ];
  }

  List<Widget> review(BuildContext context, MoodleQuestionPage shown) {
    final theme = Theme.of(context);
    final questions = shown.reviewQuestions;
    return [
      heading(context, plain(widget.module['name'])),
      if (shown.result case final result?) ...[
        const SizedBox(height: NiuSpacing.lg),
        QuestionResultView(result: result),
      ],
      if (questions != null) ...[
        const SizedBox(height: NiuSpacing.xl),
        Semantics(
          header: true,
          child: Text('題目複習', style: theme.textTheme.titleMedium),
        ),
        for (final question in questions) ...[
          const SizedBox(height: NiuSpacing.md),
          QuestionReviewCard(
            question: question,
            onOpen: () => reviewQuestion(question.id),
          ),
        ],
        if (questions.isEmpty) ...[
          const SizedBox(height: NiuSpacing.sm),
          Text(
            '校方目前未顯示本頁題目。若下方有分頁，可切換查看其他題目。',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ],
      if (shown.text.isNotEmpty) ...[
        const SizedBox(height: NiuSpacing.lg),
        NiuCard(
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            shape: const Border(),
            title: const Text('其他校方說明'),
            children: [SelectableText(shown.text)],
          ),
        ),
      ],
      ...otherActions(shown),
    ];
  }

  /// Actions without a known quiz role (e.g. review pagination) stay
  /// available, but quiet.
  List<Widget> otherActions(MoodleQuestionPage shown) => [
    for (final action in shown.actions)
      if (action.role == null) ...[
        const SizedBox(height: NiuSpacing.md),
        OutlinedButton(
          onPressed: action.disabled || !ready ? null : () => perform(action),
          child: Text(action.label),
        ),
      ],
  ];

  /// Choice, feedback, IRS… and any page that needs the school UI.
  List<Widget> generic(BuildContext context, MoodleQuestionPage shown) {
    final theme = Theme.of(context);
    final review = shown.reviewQuestions;
    return [
      Text(
        kind?.title ?? '問答',
        style: theme.textTheme.labelLarge?.copyWith(
          color: NiuColors.of(context).accent,
        ),
      ),
      const SizedBox(height: NiuSpacing.xs),
      heading(context, plain(widget.module['name'])),
      if (shown.result case final result?) ...[
        const SizedBox(height: NiuSpacing.lg),
        QuestionResultView(result: result),
      ],
      if (review != null)
        for (final question in review) ...[
          const SizedBox(height: NiuSpacing.md),
          QuestionReviewCard(
            question: question,
            onOpen: () => reviewQuestion(question.id),
          ),
        ],
      if (shown.text.isNotEmpty) ...[
        const SizedBox(height: NiuSpacing.lg),
        NiuCard(child: SelectableText(shown.text)),
      ],
      if (shown.webReason case final reason?) ...[
        const SizedBox(height: NiuSpacing.lg),
        NiuBanner(
          tone: NiuTone.accent,
          message: reason,
          actionLabel: '使用校方操作介面',
          onAction: openSchool,
        ),
      ] else ...[
        for (final field in shown.fields) ...[
          const SizedBox(height: NiuSpacing.lg),
          NiuCard(child: fieldView(field)),
        ],
        if (performing) ...[
          const SizedBox(height: NiuSpacing.lg),
          const NiuLoading(message: '正在等待校方回應，請勿重複送出'),
        ],
        for (final action in shown.actions) ...[
          const SizedBox(height: NiuSpacing.md),
          FilledButton(
            onPressed: action.disabled || !ready ? null : () => perform(action),
            child: Text(action.label),
          ),
        ],
        if (shown.result == null &&
            review == null &&
            shown.text.isEmpty &&
            shown.fields.isEmpty &&
            shown.actions.isEmpty)
          const NiuEmpty(
            icon: Icons.quiz_outlined,
            title: '尚無可顯示內容',
            message: '可能尚未開放題目，可從右上角查看校方頁面。',
          ),
      ],
    ];
  }

  // Answer state

  bool answered(MoodleQuestionField field) {
    final values = answers[field.id] ?? field.values;
    if (field.kind == 'order') {
      // Moodle shows a default order; it only counts once moved or saved.
      final question = page?.questions
          ?.where((q) => q.id == field.questionId)
          .firstOrNull;
      return values.join('\u0000') != field.values.join('\u0000') ||
          (question != null && !question.state.contains('尚未'));
    }
    if (field.options.isEmpty) {
      return (values.firstOrNull ?? '').trim().isNotEmpty;
    }
    return values.any((v) => field.options.any((o) => o.id == v && !o.blank));
  }

  /// Bubbles on this page follow native input live; other pages use
  /// Moodle's saved state.
  bool navAnswered(MoodleQuizNavItem item, MoodleQuestionPage shown) {
    final question = item.current
        ? shown.questions?.where((q) => q.number == item.number).firstOrNull
        : null;
    if (question == null) return item.state == 'answered';
    final fields = [
      for (final f in shown.fields)
        if (f.questionId == question.id) f,
    ];
    return fields.isEmpty ? item.state == 'answered' : fields.every(answered);
  }

  // Fixed bars

  Widget answerCardBar(BuildContext context, MoodleQuestionPage shown) {
    final theme = Theme.of(context);
    final colors = NiuColors.of(context);
    final items = shown.stage == 'attempt' ? shown.navigation : const [];
    final done = items.where((i) => navAnswered(i, shown)).length;
    return Material(
      color: colors.canvas,
      shape: Border(bottom: BorderSide(color: colors.hairline)),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          NiuSpacing.gutter,
          NiuSpacing.sm,
          NiuSpacing.gutter,
          items.isEmpty ? NiuSpacing.sm : 0,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (items.isNotEmpty)
                  Text(
                    '已作答 $done／${items.length}',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontFeatures: tabularFigures,
                    ),
                  ),
                const Spacer(),
                if (shown.timerSeconds case final seconds?)
                  TimerChip(seconds: seconds),
              ],
            ),
            if (items.isNotEmpty)
              SizedBox(
                height: 52,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final item in items)
                      Semantics(
                        label:
                            '第 ${item.number} 題，${navAnswered(item, shown) ? '已作答' : '未作答'}'
                            '${item.current ? '，在這一頁' : ''}',
                        button: true,
                        excludeSemantics: true,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(NiuRadius.md),
                          onTap: ready || item.current
                              ? () => jump(item, shown)
                              : null,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minWidth: 44),
                            child: Center(
                              child: AnswerBubble(
                                number: item.number,
                                filled: navAnswered(item, shown),
                                invalid: item.state == 'invalid',
                                current: item.current,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget? actionBar(BuildContext context, MoodleQuestionPage shown) {
    final colors = NiuColors.of(context);
    MoodleQuestionAction? first(Set<String> roles) =>
        shown.actions.where((a) => roles.contains(a.role)).firstOrNull;
    final primary = first(const {
      'start',
      'next',
      'finish',
      'submit',
      'confirm',
      'done',
    });
    final secondary =
        first(const {'previous', 'resume', 'cancel'}) ??
        (shown.stage == 'overview' ? first(const {'review'}) : null);
    if (primary == null && secondary == null && !performing) return null;
    final warn = primary?.role == 'confirm' || primary?.role == 'submit';
    return NiuBottomBar(
      child: performing
          ? const Row(
              children: [
                SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: NiuSpacing.md),
                Text('正在等待校方回應…'),
              ],
            )
          : Row(
              children: [
                if (secondary != null)
                  primary == null
                      ? Expanded(child: secondaryButton(secondary))
                      : secondaryButton(secondary),
                if (secondary != null && primary != null)
                  const SizedBox(width: NiuSpacing.md),
                if (primary != null)
                  Expanded(
                    child: FilledButton(
                      style: warn
                          ? FilledButton.styleFrom(
                              backgroundColor: colors.warning,
                              foregroundColor: colors.onAccent,
                            )
                          : null,
                      onPressed: primary.disabled || !ready
                          ? null
                          : () => perform(primary),
                      child: Text(
                        actionTitle(primary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget secondaryButton(MoodleQuestionAction action) => OutlinedButton(
    onPressed: action.disabled || !ready ? null : () => perform(action),
    child: Text(
      actionTitle(action),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
  );

  /// One verb per step:「交卷」is used from the last page through the school
  /// dialog.
  static String actionTitle(MoodleQuestionAction action) =>
      switch (action.role) {
        'next' => '下一頁',
        'previous' => '上一頁',
        'finish' => '檢查並交卷',
        'submit' => '交卷',
        'resume' => '返回作答',
        'review' => '複習上次作答',
        'done' => '完成複習',
        _ => action.label.replaceAll('...', '').replaceAll('…', ''),
      };
}
