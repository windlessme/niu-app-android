import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../core/analytics/app_analytics.dart';
import '../../core/session/campus_session.dart';
import '../../core/web/portal_policy.dart';
import '../../shared/shared.dart';
import '../authentication/login_screen.dart';
import '../authentication/school_reauthorization.dart';
import 'leave_application_data.dart';
import 'leave_application_service.dart';
import 'leave_notice.dart';
import 'leave_demo.dart';
import 'leave_application_sheets.dart';
import 'leave_widgets.dart';

/// The school form stays mounted behind the native UI, including its upload and
/// period-picker frames. No saved Cookie fixture or school credentials are used.
class LeaveApplicationScreen extends StatefulWidget {
  const LeaveApplicationScreen({super.key, this.session, this.gateway});
  final CampusSession? session;
  final LeaveApplicationGateway? gateway;
  @override
  State<LeaveApplicationScreen> createState() => _LeaveApplicationScreenState();
}

class _LeaveApplicationScreenState extends State<LeaveApplicationScreen>
    with WidgetsBindingObserver {
  late final session = widget.session ?? CampusSession.instance;
  late final owner = session.account;
  late final epoch = session.coordinator.epoch;
  final reason = TextEditingController();
  LeaveApplicationGateway? gateway;
  InAppWebViewController? web;
  LeaveApplicationData? data;
  LeaveSubmitResult? result;
  Uri? entry;
  bool busy = true, showWeb = false, agreed = false, deferAttachment = false;
  bool foreground = true, dirty = false, sent = false, blocked = false;
  bool mutationConsent = false;

  /// Agreed to the in-app notice; the school's own 同意 follows automatically.
  bool accepted = false;
  bool schoolDialog = false;
  String? error, schoolMessage;

  bool get current =>
      mounted &&
      session.account == owner &&
      session.coordinator.epoch == epoch &&
      !session.cleanupPending;
  bool get active =>
      current &&
      foreground &&
      (schoolDialog || (ModalRoute.of(context)?.isCurrent ?? true));
  bool get editable => !busy && !sent && !blocked && current;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    session.addListener(sessionChanged);
    session.registerCleanup(clear);
    gateway = widget.gateway ?? (session.isDemo ? DemoLeaveGateway() : null);
    WidgetsBinding.instance.addPostFrameCallback((_) => start());
  }

  void sessionChanged() {
    if (!current && mounted) {
      gateway?.dispose();
      reason.clear();
      setState(() {
        data = null;
        result = null;
        entry = null;
        blocked = true;
        busy = false;
        error = '已登出，請重新開啟申請';
      });
      unawaited(web?.stopLoading());
    }
  }

  Future<void> clear() async {
    gateway?.dispose();
    await web?.stopLoading();
    if (mounted) reason.clear();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
  }

  @override
  void dispose() {
    gateway?.dispose();
    WidgetsBinding.instance.removeObserver(this);
    session.removeListener(sessionChanged);
    session.unregisterCleanup(clear);
    unawaited(web?.stopLoading());
    reason.dispose();
    super.dispose();
  }

  Future<void> start() async {
    if (!current) return;
    if (gateway != null) {
      await initialize();
      return;
    }
    try {
      if (!session.isSignedIn) await SchoolReauthorization.restore(session);
      if (!mounted || !current) return;
      if (!session.isSignedIn) {
        await Navigator.of(context).push<bool>(
          MaterialPageRoute(builder: (_) => LoginScreen(session: session)),
        );
      }
      if (!current) return;
      final uri = await session.academicEntry();
      if (current) setState(() => entry = uri);
    } catch (_) {
      if (current) {
        setState(() {
          busy = false;
          error = '無法建立校務連線，請返回後重試';
        });
      }
    }
  }

  void accept(LeaveApplicationData value, {bool first = false}) {
    data = value;
    if (first) {
      reason.text = value.reason;
      deferAttachment = value.later;
    }
    if (!value.canDeferAttachment) deferAttachment = false;
  }

  Future<void> initialize() async {
    try {
      final initial = await gateway!.initialize();
      if (current) setState(() => accept(initial, first: true));
      // Agreed while the school page was loading: send its 同意 now.
      if (current && accepted && initial.notice != null) {
        setState(() => busy = false);
        await change(() => gateway!.agree(initial));
      }
    } catch (_) {
      if (current) {
        setState(() {
          error = '無法讀取申請表單，可開啟學校網頁確認';
          blocked = true;
        });
      }
    } finally {
      if (current) setState(() => busy = false);
    }
  }

  Future<void> change(Future<LeaveApplicationData> Function() action) async {
    if (!editable) return;
    setState(() {
      busy = true;
      error = null;
      schoolMessage = null;
    });
    try {
      final next = await action();
      if (current) {
        setState(() {
          accept(next);
          dirty = true;
        });
      }
    } catch (e) {
      if (current) {
        setState(() {
          blocked = true; // A lost postback reply must not be repeated blindly.
          error = e is LeaveApplicationException ? e.message : '更新未完成，請查看學校網頁';
        });
      }
    } finally {
      if (current) setState(() => busy = false);
    }
  }

  Future<void> dates() async {
    final now = DateTime.now().toUtc().add(const Duration(hours: 8));
    final first = DateTime(now.year - 1);
    final last = DateTime(now.year + 1, 12, 31);
    final from = parseSchoolLeaveDate(data!.start),
        to = parseSchoolLeaveDate(data!.end);
    final initial =
        from != null &&
            to != null &&
            !to.isBefore(from) &&
            !from.isBefore(first) &&
            !to.isAfter(last)
        ? DateTimeRange(start: from, end: to)
        : null;
    final selected = await showDateRangePicker(
      context: context,
      firstDate: first,
      lastDate: last,
      initialDateRange: initial,
      helpText: '請假起訖日期',
      saveText: '確認',
    );
    if (!current || selected == null) return;
    await change(
      () => gateway!.changeDates(data!, selected.start, selected.end),
    );
  }

  Future<void> periods() async {
    if (!editable) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final available = await gateway!.periods(data!);
      if (!mounted || !current) return;
      // Nothing is loading while the student chooses.
      setState(() => busy = false);
      final selected = await showModalBottomSheet<List<String>>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => LeavePeriodSheet(available: available),
      );
      if (!current) return;
      setState(() => busy = true);
      if (selected == null) {
        await gateway!.cancelPeriods();
      } else {
        final next = await gateway!.selectPeriods(data!, selected);
        if (current) {
          setState(() {
            accept(next);
            dirty = true;
          });
        }
      }
    } catch (e) {
      if (current) {
        setState(() {
          blocked = true;
          error = e is LeaveApplicationException
              ? e.message
              : '節次讀取未完成，請查看學校網頁';
        });
      }
    } finally {
      if (current) setState(() => busy = false);
    }
  }

  Future<void> attach() async {
    try {
      await pickAttachment();
    } catch (_) {
      if (current) setState(() => error = '無法讀取附件，請重新選擇檔案');
    }
  }

  Future<void> pickAttachment() async {
    if (!editable) return;
    final file = await openFile();
    if (!current || file == null) return;
    if (await file.length() > SchoolLeaveApplication.attachmentLimit) {
      if (current) setState(() => error = 'App 支援 10 MB 以下附件；較大檔案請使用學校網頁');
      return;
    }
    final bytes = await file.readAsBytes();
    if (!current) return;
    if (bytes.isEmpty ||
        !data!.extensions.contains(file.name.split('.').last.toLowerCase())) {
      setState(() => error = bytes.isEmpty ? '不能上傳空白檔案' : '校方不支援此附件格式，請重新選擇');
      return;
    }
    final ok = await confirm('上傳證明文件', '${file.name}\n附件將上傳至學校，但不會送出假單。');
    if (!current || !ok) return;
    mutationConsent = true;
    try {
      await change(() => gateway!.attach(data!, file.name, bytes));
    } finally {
      mutationConsent = false;
    }
  }

  Future<bool> confirm(String title, String message) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(child: Text(message)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('確認'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> submit() async {
    if (!editable) return;
    final invalid = data!.validate(reason.text);
    if (invalid != null) {
      setState(() => error = invalid);
      return;
    }
    await change(() => gateway!.draft(data!, reason.text, deferAttachment));
    if (!mounted || !editable) return;
    final ok =
        await showModalBottomSheet<bool>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (_) =>
              LeaveSubmitSheet(data: data!, reason: reason.text.trim()),
        ) ??
        false;
    if (!current || !ok || !editable) return;
    setState(() {
      sent = true;
      busy = true;
      error = null;
    });
    mutationConsent = true;
    try {
      final outcome = await gateway!.submit(data!);
      AppAnalytics.instance.event('leave_apply', {
        'result': outcome.confirmed ? 'success' : 'unconfirmed',
      });
      if (current) setState(() => result = outcome);
    } catch (_) {
      AppAnalytics.instance.event('leave_apply', {'result': 'unconfirmed'});
      if (current) {
        setState(
          () => result = const LeaveSubmitResult(
            message: '尚未確認送出結果，請先查詢紀錄，勿重複申請。',
          ),
        );
      }
    } finally {
      mutationConsent = false;
      if (current) setState(() => busy = false);
    }
  }

  Future<void> openSchool() async {
    if (busy || web == null) return;
    if (showWeb) {
      setState(() => showWeb = false);
      return;
    }
    // Keep the user's native text when handing the same form to the school UI.
    if (editable && data != null && data!.notice == null) {
      await change(() => gateway!.draft(data!, reason.text, deferAttachment));
    }
    if (!current) return;
    setState(() {
      showWeb = true;
      blocked = true;
      dirty = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<bool>(
      canPop: !dirty || result != null || !current,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await confirm(
          '離開申請？',
          sent ? '可能已送出假單，請先查詢紀錄，不要重複申請。' : '未送出的內容不會儲存在 App；已上傳的附件請至學校確認。',
        );
        if (current && leave) {
          setState(() => dirty = false);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) Navigator.pop(context, false);
          });
        }
      },
      child: Scaffold(
        appBar: NiuAppBar(
          title: '申請請假',
          actions: [
            if (web != null && result == null)
              // Same control as the other school-backed screens.
              NiuIconButton(
                tooltip: showWeb ? '回到 App 檢視' : '查看學校網頁',
                icon: showWeb
                    ? Icons.dashboard_rounded
                    : Icons.language_rounded,
                onPressed: busy ? null : openSchool,
              ),
          ],
        ),
        bottomNavigationBar: showWeb ? null : actionBar(context),
        body: SafeArea(
          top: false,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (entry != null)
                ExcludeSemantics(
                  excluding: !showWeb,
                  child: IgnorePointer(
                    ignoring: !showWeb,
                    child: InAppWebView(
                      initialUrlRequest: URLRequest(url: WebUri('$entry')),
                      initialSettings: InAppWebViewSettings(
                        javaScriptEnabled: true,
                        sharedCookiesEnabled: true,
                        useShouldOverrideUrlLoading: true,
                        allowFileAccess: false,
                      ),
                      shouldOverrideUrlLoading: (_, action) async =>
                          action.request.url != null &&
                              PortalPolicy.academic.allows(
                                Uri.parse('${action.request.url}'),
                              )
                          ? NavigationActionPolicy.ALLOW
                          : NavigationActionPolicy.CANCEL,
                      onWebViewCreated: (controller) {
                        web = controller;
                        gateway = SchoolLeaveApplication(
                          session: session,
                          evaluate: (script) =>
                              controller.evaluateJavascript(source: script),
                          isActive: () => active,
                        );
                        unawaited(initialize());
                      },
                      onJsAlert: (_, request) async {
                        if (current) {
                          setState(() => schoolMessage = request.message);
                        }
                        return JsAlertResponse(
                          handledByClient: true,
                          action: JsAlertResponseAction.CONFIRM,
                        );
                      },
                      onJsConfirm: (_, request) async {
                        var ok = false;
                        if (active && (mutationConsent || showWeb)) {
                          schoolDialog = true;
                          try {
                            ok = await confirm(
                              '校方確認',
                              request.message ?? '是否繼續？',
                            );
                          } finally {
                            schoolDialog = false;
                          }
                        }
                        return JsConfirmResponse(
                          handledByClient: true,
                          action: ok && current && foreground
                              ? JsConfirmResponseAction.CONFIRM
                              : JsConfirmResponseAction.CANCEL,
                        );
                      },
                    ),
                  ),
                ),
              if (!showWeb)
                Material(
                  color: NiuColors.of(context).canvas,
                  child: nativeBody(context),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> chooseType() async {
    final form = data;
    if (form == null || !editable) return;
    final value = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            NiuSpacing.gutter,
            0,
            NiuSpacing.gutter,
            NiuSpacing.xl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('假別', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: NiuSpacing.md),
              NiuGroup(
                insetDividers: NiuSpacing.lg,
                children: [
                  for (final choice in form.choices)
                    Semantics(
                      selected: choice.value == form.type,
                      inMutuallyExclusiveGroup: true,
                      child: NiuRow(
                        title: choice.label,
                        chevron: false,
                        onTap: () => Navigator.pop(context, choice.value),
                        trailing: Icon(
                          choice.value == form.type
                              ? Icons.radio_button_checked_rounded
                              : Icons.radio_button_unchecked_rounded,
                          color: choice.value == form.type
                              ? NiuColors.of(context).accent
                              : NiuColors.of(context).inkTertiary,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (!current || value == null || value == form.type) return;
    await change(() => gateway!.changeType(form, value));
  }

  /// Agree in the app; the school's 同意 is sent as soon as it is shown.
  void acceptNotice() {
    setState(() => accepted = true);
    final form = data;
    if (form?.notice != null && editable) {
      unawaited(change(() => gateway!.agree(form!)));
    }
  }

  /// Sticky primary action for the current step.
  Widget? actionBar(BuildContext context) {
    final form = data;
    if (result != null) return null;
    if (!accepted) {
      return NiuBottomBar(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CheckboxListTile(
              value: agreed,
              contentPadding: EdgeInsets.zero,
              onChanged: (v) => setState(() => agreed = v == true),
              title: const Text('我已閱讀並同意注意事項與聲明'),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            FilledButton(
              onPressed: agreed && !blocked ? acceptNotice : null,
              child: const Text('同意並開始申請'),
            ),
          ],
        ),
      );
    }
    if (form == null || form.notice != null) return null;
    if (sent) return null;
    final missing = form.validate(reason.text);
    return NiuBottomBar(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton(
            onPressed: editable ? submit : null,
            child: const Text('確認申請'),
          ),
          if (missing != null && editable) ...[
            const SizedBox(height: NiuSpacing.xs),
            Text(
              missing,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ],
        ],
      ),
    );
  }

  Widget nativeBody(BuildContext context) {
    final form = data;
    final theme = Theme.of(context);
    final colors = NiuColors.of(context);
    if (accepted &&
        result == null &&
        error == null &&
        (form == null || form.notice != null)) {
      return const Center(child: NiuLoading(message: '正在開啟請假表單'));
    }
    final banners = <Widget>[
      if (error != null)
        Padding(
          padding: const EdgeInsets.only(bottom: NiuSpacing.lg),
          child: NiuBanner(
            tone: NiuTone.warning,
            message: error!,
            actionLabel: blocked && !sent && web != null ? '在學校網頁繼續' : null,
            onAction: blocked && !sent && web != null ? openSchool : null,
          ),
        ),
      if (schoolMessage?.isNotEmpty == true)
        Padding(
          padding: const EdgeInsets.only(bottom: NiuSpacing.lg),
          child: NiuBanner(
            tone: NiuTone.accent,
            title: '學校訊息',
            message: schoolMessage!,
          ),
        ),
    ];
    final List<Widget> content;
    if (result case final result?) {
      content = [
        NiuEmpty(
          icon: result.confirmed ? NiuIcons.success : NiuIcons.warning,
          tone: result.confirmed ? NiuTone.success : NiuTone.warning,
          title: result.confirmed ? '已送出請假申請' : '請確認送出結果',
          message: result.message,
          padding: const EdgeInsets.fromLTRB(
            0,
            NiuSpacing.xxl,
            0,
            NiuSpacing.xl,
          ),
        ),
        if (result.applicationId != null)
          NiuCard(
            child: NiuKeyValue(
              label: '假單編號',
              value: result.applicationId!,
              emphasis: true,
            ),
          ),
        const SizedBox(height: NiuSpacing.md),
        Text(
          result.confirmed
              ? '送出後由學校審核，不代表已核准，可在請假紀錄查看進度。'
              : '請先到請假紀錄確認是否已建立假單，不要重複申請。',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: NiuSpacing.xl),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('返回請假紀錄'),
        ),
      ];
    } else if (!accepted) {
      content = [
        Container(
          padding: const EdgeInsets.all(NiuSpacing.lg),
          decoration: BoxDecoration(
            color: NiuTone.error.background(context),
            borderRadius: BorderRadius.circular(NiuRadius.card),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '重要聲明',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: colors.error,
                ),
              ),
              const SizedBox(height: NiuSpacing.xs),
              Text(
                leaveDisclaimer,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.error,
                  height: 1.6,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: NiuSpacing.xl),
        Text('請假注意事項', style: theme.textTheme.headlineSmall),
        const SizedBox(height: NiuSpacing.lg),
        NiuCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, (title, items))
                  in leaveNoticeSections.indexed) ...[
                if (i > 0) const SizedBox(height: NiuSpacing.lg),
                Text(title, style: theme.textTheme.titleSmall),
                for (final item in items)
                  Padding(
                    padding: const EdgeInsets.only(top: NiuSpacing.xs),
                    child: Text('・$item', style: theme.textTheme.bodyMedium),
                  ),
              ],
            ],
          ),
        ),
      ];
    } else if (form != null) {
      final dated = form.start.isNotEmpty && form.end.isNotEmpty;
      final periodEntries = form.periodEntries;
      content = [
        Text('送出後由學校審核，核准前可在請假紀錄查看進度。', style: theme.textTheme.bodySmall),
        NiuSection(
          title: '請假內容',
          child: NiuGroup(
            children: [
              NiuRow(
                icon: NiuIcons.leave,
                hue: NiuHue.pink,
                title: '假別',
                value: form.choices.any((c) => c.value == form.type)
                    ? form.typeLabel
                    : '請選擇',
                onTap: editable ? chooseType : null,
                chevron: true,
              ),
              NiuRow(
                icon: NiuIcons.calendar,
                hue: NiuHue.red,
                title: '日期',
                subtitle: dated
                    ? leaveRangeSummary(form.start, form.end)
                    : null,
                value: dated ? null : '請選擇',
                onTap: editable ? dates : null,
                chevron: true,
              ),
              NiuRow(
                icon: NiuIcons.time,
                hue: NiuHue.orange,
                title: '節次',
                subtitle: dated ? null : '先選擇日期',
                value: form.hasPeriods ? '${form.total ?? '-'} 節' : '請選擇',
                onTap: editable && dated ? periods : null,
                chevron: true,
              ),
            ],
          ),
        ),
        if (periodEntries.isNotEmpty) ...[
          const SizedBox(height: NiuSpacing.md),
          NiuCard(child: LeavePeriodSchedule(entries: periodEntries)),
        ],
        NiuSection(
          title: '請假事由',
          child: NiuCard(
            padding: const EdgeInsets.fromLTRB(
              NiuSpacing.lg,
              NiuSpacing.sm,
              NiuSpacing.lg,
              NiuSpacing.xs,
            ),
            child: TextField(
              controller: reason,
              enabled: editable,
              maxLength: form.reasonLimit,
              minLines: 3,
              maxLines: 8,
              onChanged: (_) => setState(() => dirty = true),
              decoration: const InputDecoration(
                hintText: '簡單說明請假原因',
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: NiuSpacing.sm),
              ),
            ),
          ),
        ),
        NiuSection(
          title: '證明文件',
          subtitle: form.extensions.isEmpty
              ? null
              : '${form.extensions.map((e) => e.toUpperCase()).join('、')}，10 MB 以下',
          child: NiuGroup(
            children: [
              for (final attachment in form.attachments)
                NiuRow(
                  icon: NiuIcons.file,
                  hue: NiuHue.cyan,
                  title: attachment,
                  chevron: false,
                ),
              NiuRow(
                icon: NiuIcons.upload,
                hue: NiuHue.blue,
                title: form.attachments.isEmpty ? '上傳證明文件' : '再上傳一份',
                subtitle: '上傳後仍需按「確認申請」才會送出',
                onTap: editable && form.extensions.isNotEmpty ? attach : null,
              ),
              if (form.canDeferAttachment)
                NiuRow(
                  icon: NiuIcons.history,
                  hue: NiuHue.gray,
                  title: '事後補件',
                  subtitle: '先送出假單，之後再補上證明文件',
                  chevron: false,
                  trailing: Switch(
                    value: deferAttachment,
                    onChanged: editable
                        ? (v) => setState(() {
                            deferAttachment = v;
                            dirty = true;
                          })
                        : null,
                  ),
                ),
            ],
          ),
        ),
      ];
    } else {
      content = const [];
    }
    return Column(
      children: [
        SizedBox(
          height: 2,
          child: busy
              ? LinearProgressIndicator(
                  minHeight: 2,
                  borderRadius: BorderRadius.zero,
                  color: colors.accent,
                )
              : null,
        ),
        Expanded(
          child: AbsorbPointer(
            // The notice stays readable while the school page loads.
            absorbing: busy && accepted,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                NiuSpacing.gutter,
                NiuSpacing.md,
                NiuSpacing.gutter,
                NiuSpacing.huge,
              ),
              children: [...banners, ...content],
            ),
          ),
        ),
      ],
    );
  }
}
