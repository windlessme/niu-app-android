import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../core/analytics/app_analytics.dart';
import '../../core/session/campus_session.dart';
import '../../core/web/portal_policy.dart';
import '../../shared/shared.dart';
import '../authentication/school_reauthorization.dart';
import 'leave_application_data.dart';
import 'leave_application_service.dart';
import 'leave_manage.dart';

enum LeaveWithdrawOutcome {
  /// A fresh 學生請假修改 query no longer lists the form.
  withdrawn,

  /// The school handled the postback, yet the form is still listed.
  stillListed,

  /// The postback was sent; its outcome could not be read.
  unconfirmed,
}

abstract class LeaveWithdrawGateway {
  /// Throws [LeaveApplicationException] when nothing was sent.
  Future<LeaveWithdrawOutcome> withdraw(String formNo);
}

class DemoLeaveWithdraw implements LeaveWithdrawGateway {
  @override
  Future<LeaveWithdrawOutcome> withdraw(String formNo) async {
    await Future<void>.delayed(const Duration(milliseconds: 800));
    return LeaveWithdrawOutcome.withdrawn;
  }
}

/// 撤回 through the school's own list: its delete link and confirm, then a
/// new query to check. The only school confirm accepted is the delete prompt,
/// once, after the student has confirmed in the app.
class SchoolLeaveWithdraw implements LeaveWithdrawGateway {
  SchoolLeaveWithdraw({
    required this.evaluate,
    required this.guard,
    this.interval = const Duration(milliseconds: 500),
    this.budget = const Duration(seconds: 60),
  });
  final Future<dynamic> Function(String script) evaluate;

  /// Throws when the screen, account or session no longer allows this.
  final void Function() guard;
  final Duration interval, budget;

  /// Set while the school's delete confirm may appear.
  bool expectingConfirm = false;

  /// The last postback state and list check, for analytics.
  String state = 'none', check = 'none';

  bool acceptsConfirm(String? message) {
    final text = message ?? '';
    if (!expectingConfirm || !(text.contains('刪除') || text.contains('撤回'))) {
      return false;
    }
    expectingConfirm = false;
    return true;
  }

  Future<dynamic> _read(String script) async {
    guard();
    try {
      return await evaluate(script);
    } catch (_) {
      // A postback can replace the JavaScript context mid-read.
      return null;
    } finally {
      guard();
    }
  }

  Future<void> _settledList() async {
    final clock = Stopwatch()..start();
    while (clock.elapsed < budget) {
      final step = await _read(leaveManageNavigation);
      if (step == 'session-expired') {
        throw const LeaveApplicationException('校務登入已過期，請重新登入');
      }
      if (step == 'ready') return;
      await Future<void>.delayed(interval);
    }
    throw const LeaveApplicationException('無法開啟學校的假單列表，請稍後再試');
  }

  @override
  Future<LeaveWithdrawOutcome> withdraw(String formNo) async {
    await _settledList();
    final raw = await _read(leaveManageExtract);
    final actions = raw is String
        ? LeaveActions.fromSnapshot(jsonDecode(raw))
        : const <LeaveActions>[];
    if (!actions.any((a) => a.formNo == formNo && a.withdraw)) {
      throw const LeaveActionMissing();
    }
    expectingConfirm = true;
    final scheduled = await _read(leaveWithdraw(formNo));
    if (scheduled != 'scheduled') {
      expectingConfirm = false;
      throw scheduled == 'missing'
          ? const LeaveActionMissing()
          : const LeaveApplicationException('學校的假單列表格式已變更，沒有撤回');
    }
    // The school's confirm, then its postback. Leaving early could abort it.
    var posted = false;
    final clock = Stopwatch()..start();
    while (clock.elapsed < const Duration(seconds: 15)) {
      await Future<void>.delayed(interval);
      final now = await _read(leaveWithdrawState);
      if (now is String) state = now;
      if (now == 'declined') {
        throw const LeaveApplicationException('學校的確認沒有通過，沒有撤回');
      }
      if (now == 'waiting' || now == 'reloaded' || now == 'removed') {
        posted = true;
      }
      // A replaced page can no longer be read; the list check decides.
      if (now == null && posted) break;
      if (now == 'reloaded' || now == 'removed' || now == 'expired') break;
    }
    expectingConfirm = false;
    if (!posted && state == 'confirming') {
      // The school's prompt was never answered: nothing was sent.
      throw const LeaveApplicationException('學校的確認沒有完成，沒有撤回');
    }
    // 學生請假修改, read again, is the answer either way.
    try {
      await _read(leaveManageReset);
      await _settledList();
      final listed = await _read(leaveManageListed(formNo));
      if (listed is String) check = listed;
      // Gone, or still listed without its withdraw link: the school took it.
      if (listed == 'gone' || listed == 'locked') {
        return LeaveWithdrawOutcome.withdrawn;
      }
      if (listed == 'listed') return LeaveWithdrawOutcome.stillListed;
    } on LeaveApplicationException {
      check = 'failed';
    }
    return LeaveWithdrawOutcome.unconfirmed;
  }
}

/// Runs one 撤回 with the school page kept under a progress view.
/// Pops true once anything was sent, so the records are read again.
class LeaveWithdrawScreen extends StatefulWidget {
  const LeaveWithdrawScreen({
    super.key,
    required this.formNo,
    this.session,
    this.gateway,
  });
  final String formNo;
  final CampusSession? session;
  final LeaveWithdrawGateway? gateway;
  @override
  State<LeaveWithdrawScreen> createState() => _LeaveWithdrawScreenState();
}

class _LeaveWithdrawScreenState extends State<LeaveWithdrawScreen> {
  late final session = widget.session ?? CampusSession.instance;
  late final owner = session.account;
  late final epoch = session.coordinator.epoch;
  LeaveWithdrawGateway? gateway;
  Uri? entry;
  LeaveWithdrawOutcome? outcome;
  String? error;
  bool started = false;

  bool get current =>
      mounted &&
      session.account == owner &&
      session.coordinator.epoch == epoch &&
      !session.cleanupPending;

  @override
  void initState() {
    super.initState();
    gateway = widget.gateway ?? (session.isDemo ? DemoLeaveWithdraw() : null);
    WidgetsBinding.instance.addPostFrameCallback((_) => start());
  }

  Future<void> start() async {
    if (gateway != null) return run();
    try {
      if (!session.isSignedIn) await SchoolReauthorization.restore(session);
      if (!current) return;
      if (!session.isSignedIn) {
        setState(() => error = '校務登入已過期，請重新登入');
        return;
      }
      final uri = await session.academicEntry();
      if (current) setState(() => entry = uri);
    } catch (_) {
      if (current) setState(() => error = '無法連上學校系統，請稍後再試');
    }
  }

  Future<void> run() async {
    if (started || gateway == null) return;
    started = true;
    try {
      final result = await gateway!.withdraw(widget.formNo);
      final school = gateway;
      AppAnalytics.instance.event('leave_withdraw', {
        'result': result == LeaveWithdrawOutcome.withdrawn
            ? 'success'
            : 'unconfirmed',
        if (school is SchoolLeaveWithdraw) ...{
          'state': school.state,
          'check': school.check,
        },
      });
      if (current) setState(() => outcome = result);
    } on LeaveApplicationException catch (e) {
      AppAnalytics.instance.event('leave_withdraw', {'result': 'failure'});
      if (current) setState(() => error = e.message);
    } catch (_) {
      if (current) setState(() => error = '無法撤回，請稍後再試');
    }
  }

  void guard() {
    if (!current) throw const LeaveApplicationException('已登出，沒有撤回');
  }

  @override
  Widget build(BuildContext context) {
    final done = outcome != null || error != null;
    return PopScope<bool>(
      // Leaving while the postback runs could abort it.
      canPop: done,
      child: Scaffold(
        appBar: NiuAppBar(title: '撤回假單', showBack: done),
        body: Stack(
          fit: StackFit.expand,
          children: [
            if (entry != null)
              ExcludeSemantics(
                child: IgnorePointer(
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
                      gateway = SchoolLeaveWithdraw(
                        evaluate: (script) =>
                            controller.evaluateJavascript(source: script),
                        guard: guard,
                      );
                      unawaited(run());
                    },
                    onJsAlert: (_, _) async => JsAlertResponse(
                      handledByClient: true,
                      action: JsAlertResponseAction.CONFIRM,
                    ),
                    onJsConfirm: (_, request) async {
                      final school = gateway;
                      final ok =
                          current &&
                          school is SchoolLeaveWithdraw &&
                          school.acceptsConfirm(request.message);
                      return JsConfirmResponse(
                        handledByClient: true,
                        action: ok
                            ? JsConfirmResponseAction.CONFIRM
                            : JsConfirmResponseAction.CANCEL,
                      );
                    },
                  ),
                ),
              ),
            Material(
              color: NiuColors.of(context).canvas,
              child: Padding(
                padding: const EdgeInsets.all(NiuSpacing.gutter),
                child: Center(child: body(context)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget body(BuildContext context) {
    if (error case final message?) {
      return NiuEmpty(
        icon: NiuIcons.warning,
        tone: NiuTone.warning,
        title: '沒有撤回',
        message: message,
        action: FilledButton.tonal(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('返回'),
        ),
      );
    }
    final (icon, tone, title, message) = switch (outcome) {
      null => (
        NiuIcons.pending,
        NiuTone.neutral,
        '正在撤回假單',
        '正在等學校處理並重新查詢確認，請勿離開。',
      ),
      LeaveWithdrawOutcome.withdrawn => (
        NiuIcons.success,
        NiuTone.success,
        '已撤回假單',
        '假單 ${widget.formNo} 已不在學校的假單列表中。',
      ),
      LeaveWithdrawOutcome.stillListed => (
        NiuIcons.warning,
        NiuTone.warning,
        '撤回結果尚未確認',
        '已送出撤回，但學校列表仍顯示這張假單。請重新整理或到學校網頁查看，不要重複撤回。',
      ),
      LeaveWithdrawOutcome.unconfirmed => (
        NiuIcons.warning,
        NiuTone.warning,
        '撤回結果尚未確認',
        '已送出撤回，但無法確認結果。請重新整理或到學校網頁查看，不要重複撤回。',
      ),
    };
    if (outcome == null) return NiuLoading(message: '$title\n$message');
    return NiuEmpty(
      icon: icon,
      tone: tone,
      title: title,
      message: message,
      action: FilledButton(
        onPressed: () => Navigator.pop(context, true),
        child: const Text('返回請假紀錄'),
      ),
    );
  }
}
