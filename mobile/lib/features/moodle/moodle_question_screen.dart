import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../core/analytics/app_analytics.dart';
import '../../shared/shared.dart';
import 'moodle_demo.dart';
import 'moodle_question_demo.dart';
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
  Future<String?> _run(String source) async {
    final value = await web.evaluateJavascript(source: source);
    return value is String ? value : null;
  }

  @override
  Future<String?> snapshot() async =>
      await web.isLoading() ? null : _run(moodleQuestionSnapshot);
  @override
  Future<String?> perform(
    String revision,
    String actionId,
    Map<String, List<String>> answers,
  ) => _run(moodleQuestionPerform(revision, actionId, answers));
  @override
  Future<String?> stage(String revision, Map<String, List<String>> answers) =>
      _run(moodleQuestionStage(revision, answers));
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
  String? error;
  bool loading = true, showWeb = false, performing = false, reading = false;
  bool foreground = true, syncingPage = false, needsAnswerSync = false;
  int failures = 0;
  String? submittedRevision;
  DateTime? submissionStarted;

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

  void accept(MoodleQuestionPage next) {
    final previous = page;
    setState(() {
      loading = false;
      if (previous?.revision != next.revision || needsAnswerSync) {
        final edited =
            previous != null &&
            !performing &&
            !needsAnswerSync &&
            jsonEncode(answers) != jsonEncode(previous.values);
        error = edited ? '校方題目或選項已更新，請重新確認答案。' : null;
        answers = next.values;
        for (final field in next.fields) {
          if (!field.isChoice) {
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

  Future<void> perform(MoodleQuestionAction action) async {
    final shown = page;
    if (!ready || shown == null || shown.webReason != null) return;
    if (!action.isNavigation) {
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
    setState(() {
      performing = true;
      error = null;
      submittedRevision = shown.revision;
      submissionStarted = DateTime.now();
    });
    try {
      final result = await driver!.perform(shown.revision, action.id, values);
      if (!mounted) return;
      if (result != 'invoked') {
        setState(() {
          performing = false;
          submittedRevision = null;
          submissionStarted = null;
          error = result == 'invalid'
              ? '請確認必填欄位、字數與輸入格式後再送出。'
              : '題目或操作已變更，請重新確認目前內容。';
        });
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
    final theme = Theme.of(context);
    final review = shown.reviewQuestions;
    final hasExtra = shown.result != null || review != null;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        NiuSpacing.gutter,
        NiuSpacing.md,
        NiuSpacing.gutter,
        NiuSpacing.huge,
      ),
      children: [
        Text(
          plain(widget.module['name']),
          style: theme.textTheme.headlineSmall,
        ),
        if (error case final message?) ...[
          const SizedBox(height: NiuSpacing.md),
          NiuBanner(tone: NiuTone.warning, message: message),
        ],
        if (shown.result case final result?) ...[
          const SizedBox(height: NiuSpacing.lg),
          _ResultCard(result: result),
        ],
        if (review != null)
          NiuSection(
            title: '題目複習',
            subtitle: '依校方開放的內容顯示，僅供複習，無法修改作答。',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (review.isEmpty)
                  Text(
                    '校方目前未顯示本頁題目。若下方有分頁，可切換查看其他題目。',
                    style: theme.textTheme.bodySmall,
                  ),
                for (final question in review)
                  Padding(
                    padding: const EdgeInsets.only(bottom: NiuSpacing.md),
                    child: _ReviewCard(
                      question: question,
                      onOpen: () => reviewQuestion(question.id),
                    ),
                  ),
              ],
            ),
          ),
        if (shown.text.isNotEmpty) ...[
          const SizedBox(height: NiuSpacing.lg),
          if (hasExtra && shown.fields.isEmpty)
            NiuCard(
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                shape: const Border(),
                title: const Text('其他校方說明'),
                children: [SelectableText(shown.text)],
              ),
            )
          else
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
            fieldView(context, field),
          ],
          if (performing) ...[
            const SizedBox(height: NiuSpacing.lg),
            const NiuLoading(message: '正在等待校方回應，請勿重複送出'),
          ],
          for (final action in shown.actions) ...[
            const SizedBox(height: NiuSpacing.md),
            FilledButton(
              onPressed: action.disabled || !ready
                  ? null
                  : () => perform(action),
              child: Text(action.label),
            ),
          ],
          if (!hasExtra &&
              shown.text.isEmpty &&
              shown.fields.isEmpty &&
              shown.actions.isEmpty)
            const NiuEmpty(
              icon: Icons.quiz_outlined,
              title: '尚無可顯示內容',
              message: '可能尚未開放題目，可從右上角查看校方頁面。',
            ),
        ],
      ],
    );
  }

  Widget fieldView(BuildContext context, MoodleQuestionField field) {
    final theme = Theme.of(context);
    final enabled = !field.disabled && ready;
    final chosen = answers[field.id] ?? const <String>[];
    return NiuCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            field.label + (field.required ? '（必填）' : ''),
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: NiuSpacing.sm),
          if (field.kind == 'single')
            RadioGroup<String>(
              groupValue: chosen.firstOrNull,
              onChanged: (v) {
                if (enabled && v != null) {
                  setState(() => answers[field.id] = [v]);
                }
              },
              child: Column(
                children: [
                  for (final option in field.options)
                    RadioListTile<String>(
                      contentPadding: EdgeInsets.zero,
                      value: option.id,
                      enabled: enabled && !option.disabled,
                      title: Text(option.label),
                    ),
                ],
              ),
            )
          else if (field.isChoice)
            for (final option in field.options)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: chosen.contains(option.id),
                title: Text(option.label),
                onChanged: enabled && !option.disabled
                    ? (v) => setState(() {
                        // Read the answers now, not as they were at build.
                        final now = answers[field.id] ?? const <String>[];
                        answers[field.id] = [
                          for (final o in field.options)
                            if (o.id == option.id
                                ? v == true
                                : now.contains(o.id))
                              o.id,
                        ];
                      })
                    : null,
              )
          else
            TextField(
              controller: text(field),
              enabled: enabled,
              minLines: field.kind == 'longText' ? 3 : 1,
              maxLines: field.kind == 'longText' ? 8 : 1,
              decoration: const InputDecoration(hintText: '輸入答案'),
              onChanged: (v) => answers[field.id] = [v],
            ),
        ],
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.result});
  final MoodleQuestionResult result;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return NiuCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (result.grade case final grade?)
            NiuStat(label: result.gradeLabel ?? '成績', value: grade),
          for (final d in result.information)
            NiuKeyValue(label: d.label, value: d.value),
          for (final attempt in result.attempts) ...[
            const SizedBox(height: NiuSpacing.md),
            Text(attempt.title, style: theme.textTheme.titleSmall),
            for (final d in attempt.details)
              NiuKeyValue(label: d.label, value: d.value),
          ],
          for (final notice in result.notices) ...[
            const SizedBox(height: NiuSpacing.sm),
            Text(notice, style: theme.textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.question, required this.onOpen});
  final MoodleReviewQuestion question;
  final VoidCallback onOpen;

  static (String, NiuTone)? verdict(String? value) => switch (value) {
    'correct' => ('正確', NiuTone.success),
    'partiallycorrect' => ('部分正確', NiuTone.warning),
    'incorrect' => ('錯誤', NiuTone.error),
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = NiuColors.of(context);
    Widget block(String label, String value) => value.isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(top: NiuSpacing.sm),
            child: NiuWell(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: theme.textTheme.labelMedium),
                  const SizedBox(height: 2),
                  SelectableText(value),
                ],
              ),
            ),
          );
    return NiuCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(question.title, style: theme.textTheme.titleMedium),
              ),
              if (verdict(question.verdict) case (final label, final tone))
                NiuBadge(label: label, tone: tone),
            ],
          ),
          if ([question.status, question.mark].any((s) => s.isNotEmpty))
            Text(
              [
                question.status,
                question.mark,
              ].where((s) => s.isNotEmpty).join('・'),
              style: theme.textTheme.bodySmall,
            ),
          if (question.text.isNotEmpty) ...[
            const SizedBox(height: NiuSpacing.sm),
            SelectableText(question.text),
          ],
          if (question.prompt.isNotEmpty)
            Text(question.prompt, style: theme.textTheme.bodySmall),
          for (final choice in question.choices)
            Padding(
              padding: const EdgeInsets.only(top: NiuSpacing.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    choice.selected
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: 18,
                    color: switch (choice.verdict) {
                      'correct' => colors.success,
                      'incorrect' => colors.error,
                      'partiallycorrect' => colors.warning,
                      _ => colors.inkTertiary,
                    },
                  ),
                  const SizedBox(width: NiuSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(choice.text),
                        if (choice.feedback.isNotEmpty)
                          Text(
                            choice.feedback,
                            style: theme.textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          block('你的作答', question.responses.join('\n')),
          block('正確答案', question.correctAnswer),
          block('作答回饋', question.feedback),
          block('題目解析', question.generalFeedback),
          block('教師評語', question.comment),
          if (question.webReason case final reason?) ...[
            const SizedBox(height: NiuSpacing.sm),
            Text(reason, style: theme.textTheme.bodySmall),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(onPressed: onOpen, child: const Text('查看本題完整內容')),
          ),
        ],
      ),
    );
  }
}
