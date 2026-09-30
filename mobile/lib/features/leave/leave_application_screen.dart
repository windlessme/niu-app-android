import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../core/session/campus_session.dart';
import '../../core/web/portal_policy.dart';
import '../../shared/shared.dart';
import '../authentication/login_screen.dart';
import '../authentication/school_reauthorization.dart';
import 'leave_application_data.dart';
import 'leave_application_service.dart';

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
    gateway = widget.gateway;
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
      final chosen = <String>{
        for (final p in available)
          if (p.selected) p.value,
      };
      final selected = await showModalBottomSheet<List<String>>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (context) => StatefulBuilder(
          builder: (context, update) => SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(NiuSpacing.gutter),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('選擇請假節次', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: NiuSpacing.md),
                  if (available.isEmpty)
                    const NiuEmpty(
                      title: '這段日期沒有可選節次',
                      message: '請調整日期或查看學校網頁。',
                    ),
                  for (final p in available)
                    CheckboxListTile(
                      value: chosen.contains(p.value),
                      onChanged: (value) => update(() {
                        value == true
                            ? chosen.add(p.value)
                            : chosen.remove(p.value);
                      }),
                      title: Text('${p.date} · ${p.period}'),
                      subtitle: p.course.isEmpty ? null : Text(p.course),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                  const SizedBox(height: NiuSpacing.md),
                  FilledButton(
                    onPressed: chosen.isEmpty
                        ? null
                        : () => Navigator.pop(context, chosen.toList()),
                    child: const Text('確認節次'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      if (!current) return;
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
    if (!editable) return;
    final ok = await confirm(
      '確認送出請假',
      '${data!.typeLabel}\n${displayLeaveDate(data!.start)}–${displayLeaveDate(data!.end)}\n${data!.total ?? '-'} 節\n\n${reason.text.trim()}\n\n送出後將進入校方審核，不代表已核准。',
    );
    if (!current || !ok || !editable) return;
    setState(() {
      sent = true;
      busy = true;
      error = null;
    });
    mutationConsent = true;
    try {
      final outcome = await gateway!.submit(data!);
      if (current) setState(() => result = outcome);
    } catch (_) {
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
            if (web != null)
              NiuIconButton(
                icon: showWeb ? NiuIcons.back : NiuIcons.external,
                tooltip: showWeb ? '返回 App' : '學校網頁',
                onPressed: busy ? null : openSchool,
              ),
          ],
        ),
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

  Widget nativeBody(BuildContext context) {
    final form = data;
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        NiuSpacing.gutter,
        NiuSpacing.md,
        NiuSpacing.gutter,
        NiuSpacing.huge,
      ),
      children: [
        if (error != null) NiuBanner(tone: NiuTone.warning, message: error!),
        if (schoolMessage?.isNotEmpty == true)
          NiuBanner(tone: NiuTone.accent, message: schoolMessage!),
        if (busy) const NiuLoading(message: '正在更新校方表單'),
        if (result case final result?) ...[
          NiuSection(
            first: true,
            title: result.confirmed ? '已建立假單' : '請確認送出結果',
            child: NiuCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (result.applicationId != null)
                    NiuKeyValue(label: '假單編號', value: result.applicationId!),
                  Text(result.message),
                  const SizedBox(height: NiuSpacing.lg),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('返回並更新紀錄'),
                  ),
                ],
              ),
            ),
          ),
        ] else if (form?.notice case final String notice) ...[
          Text('請假注意事項', style: theme.textTheme.titleLarge),
          const SizedBox(height: NiuSpacing.md),
          NiuCard(child: Text(notice, style: theme.textTheme.bodyMedium)),
          CheckboxListTile(
            value: agreed,
            onChanged: busy ? null : (v) => setState(() => agreed = v == true),
            title: const Text('已閱讀並同意校方請假注意事項'),
            controlAffinity: ListTileControlAffinity.leading,
          ),
          FilledButton(
            onPressed: editable && agreed
                ? () => change(() => gateway!.agree(form!))
                : null,
            child: const Text('開始申請'),
          ),
        ] else if (form != null) ...[
          NiuSection(
            first: true,
            title: '假別與日期',
            child: NiuCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: form.choices.any((c) => c.value == form.type)
                        ? form.type
                        : null,
                    key: ValueKey(form.type),
                    isExpanded: true,
                    itemHeight: null,
                    decoration: const InputDecoration(labelText: '請假類別'),
                    items: [
                      for (final choice in form.choices)
                        DropdownMenuItem(
                          value: choice.value,
                          child: Text(
                            choice.label,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: editable
                        ? (value) {
                            if (value != null) {
                              unawaited(
                                change(() => gateway!.changeType(form, value)),
                              );
                            }
                          }
                        : null,
                  ),
                  const SizedBox(height: NiuSpacing.md),
                  OutlinedButton.icon(
                    onPressed: editable ? dates : null,
                    icon: const Icon(Icons.date_range_outlined),
                    label: Text(
                      '${displayLeaveDate(form.start)} – ${displayLeaveDate(form.end)}',
                    ),
                  ),
                ],
              ),
            ),
          ),
          NiuSection(
            title: '請假節次',
            action: TextButton(
              onPressed:
                  editable && form.start.isNotEmpty && form.end.isNotEmpty
                  ? periods
                  : null,
              child: const Text('選擇節次'),
            ),
            child: NiuCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${form.total ?? '-'} 節',
                    style: theme.textTheme.headlineSmall,
                  ),
                  if (!form.hasPeriods) const Text('尚未選擇節次'),
                  for (final row in form.periods)
                    Padding(
                      padding: const EdgeInsets.only(top: NiuSpacing.sm),
                      child: Text(row.join(' · ')),
                    ),
                ],
              ),
            ),
          ),
          NiuSection(
            title: '請假事由',
            child: TextField(
              controller: reason,
              enabled: editable,
              maxLength: form.reasonLimit,
              minLines: 3,
              maxLines: 6,
              onChanged: (_) => setState(() => dirty = true),
              decoration: const InputDecoration(hintText: '填寫請假原因'),
            ),
          ),
          NiuSection(
            title: '證明文件',
            child: NiuCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (form.attachments.isEmpty) const Text('尚未附加文件'),
                  Text('App 支援 10 MB 以下檔案', style: theme.textTheme.labelMedium),
                  for (final attachment in form.attachments) Text(attachment),
                  const SizedBox(height: NiuSpacing.sm),
                  OutlinedButton.icon(
                    onPressed: editable && form.extensions.isNotEmpty
                        ? attach
                        : null,
                    icon: const Icon(Icons.attach_file),
                    label: const Text('選擇並上傳附件'),
                  ),
                  if (form.canDeferAttachment)
                    CheckboxListTile(
                      value: deferAttachment,
                      onChanged: editable
                          ? (v) => setState(() {
                              deferAttachment = v == true;
                              dirty = true;
                            })
                          : null,
                      title: const Text('事後補檔'),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: NiuSpacing.xxl),
          FilledButton.icon(
            onPressed: editable ? submit : null,
            icon: const Icon(Icons.send_outlined),
            label: const Text('確認申請'),
          ),
        ],
        if (blocked && !sent && web != null)
          TextButton(onPressed: openSchool, child: const Text('在學校網頁繼續')),
      ],
    );
  }
}
