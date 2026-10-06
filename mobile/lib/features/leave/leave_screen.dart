import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/demo/demo_data.dart';
import '../../core/session/campus_session.dart';
import '../academic_portal/academic_portal_screen.dart';
import '../../shared/shared.dart';
import 'leave_application_data.dart';
import 'leave_repository.dart';
import 'leave_widgets.dart';
import 'leave_application_screen.dart';
import 'leave_manage.dart';
import 'leave_withdraw_screen.dart';

class LeaveScreen extends StatefulWidget {
  const LeaveScreen({super.key, this.session});
  final CampusSession? session;
  @override
  State<LeaveScreen> createState() => _LeaveScreenState();
}

class _LeaveScreenState extends State<LeaveScreen> {
  late final session = widget.session ?? CampusSession.instance;
  late final repository = LeaveRepository(session);
  Map<String, dynamic> snapshots = {};
  bool loading = true, busy = false;
  String? error;

  /// Details already loaded by themselves since the page was opened, so a
  /// failed or cancelled read is not retried in a loop.
  final _autoLoaded = <String>{};
  @override
  void initState() {
    super.initState();
    session.addListener(changed);
    restore();
  }

  void changed() {
    if (!session.hasLocalAccount && mounted) setState(() => snapshots = {});
  }

  Future<void> restore() async {
    try {
      final data = await repository.restore();
      if (mounted) setState(() => snapshots = data);
    } catch (_) {
      if (mounted) setState(() => error = '讀不到保存的請假資料');
    } finally {
      if (mounted) setState(() => loading = false);
    }
    if (mounted && snapshots.isEmpty && error == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
        await refreshAll();
      });
    }
  }

  @override
  void dispose() {
    session.removeListener(changed);
    unawaited(repository.dispose());
    super.dispose();
  }

  /// Reads one part from the school; true once it is saved.
  Future<bool> open({
    String? keyName,
    Map<String, dynamic>? record,
    bool application = false,
    int page = 1,
  }) async {
    if (busy || !session.hasLocalAccount) return false;
    if (application) {
      final applicationOwner = session.account;
      final applicationEpoch = session.coordinator.epoch;
      setState(() => busy = true);
      bool? checkRecords;
      try {
        checkRecords = await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) => LeaveApplicationScreen(session: session),
          ),
        );
      } finally {
        if (mounted) setState(() => busy = false);
      }
      // A response timeout is not a reason to resend. Return to the existing
      // read-only query so the student can check the school's actual records.
      if (mounted &&
          session.hasLocalAccount &&
          checkRecords == true &&
          session.account == applicationOwner &&
          session.coordinator.epoch == applicationEpoch) {
        await open(keyName: 'list');
      }
      return false;
    }
    final owner = session.account!;
    final epoch = session.coordinator.epoch;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final value = await Navigator.of(context).push<Map<String, dynamic>>(
        MaterialPageRoute(
          builder: (context) => AcademicPortalScreen(
            title: application
                ? '申請請假'
                : keyName == 'actions'
                ? '假單操作'
                : keyName == 'statistics'
                ? '請假統計'
                : record != null
                ? '請假明細'
                : '請假紀錄',
            session: session,
            navigationScript: keyName == 'actions'
                ? leaveManageNavigation
                : leaveMenuNavigation(
                    application || keyName == 'statistics',
                    agreeForStatistics: keyName == 'statistics',
                  ),
            extractScript: application
                ? null
                : keyName == 'actions'
                ? leaveManageExtract
                : keyName == 'statistics'
                ? leaveStatisticsExtract
                : record != null
                ? leaveDetailWithWorkflowExtract()
                : leaveInFrames(leaveListExtract),
            prepareScript:
                application || keyName == 'statistics' || keyName == 'actions'
                ? null
                : record != null
                ? leaveDetailPrepare(
                    '${record['假單序號']}',
                    int.tryParse('${record['_page']}') ?? 1,
                  )
                : leaveInFrames(leavePagePrepare(page)),
            demoSnapshot: () => keyName == 'actions'
                ? DemoData.leaveActions
                : keyName == 'statistics'
                ? DemoData.leaveStatistics
                : record != null
                ? DemoData.leaveDetail('${record['假單序號']}')
                : DemoData.leaveList,
            onSnapshot: (value, _) async {
              if (context.mounted) {
                Navigator.pop(context, Map<String, dynamic>.from(value as Map));
              }
            },
          ),
        ),
      );
      if (value == null) return false;
      repository.guard(epoch, owner);
      if (record != null && mounted) {
        if (!value.containsKey('workflow')) {
          final previous = snapshots['detail:${record['假單序號']}'];
          if (previous is Map &&
              previous['data'] is Map &&
              previous['data']['workflow'] is List) {
            value['workflow'] = previous['data']['workflow'];
            value['workflowUpdatedAt'] =
                previous['data']['workflowUpdatedAt'] ?? previous['updatedAt'];
          }
          value['workflowStale'] = true;
        } else {
          value['workflowUpdatedAt'] = DateTime.now().toUtc().toIso8601String();
          value['workflowStale'] = false;
        }
      }
      final key = keyName ?? 'detail:${record!['假單序號']}';
      final next = {
        ...snapshots,
        key: {
          'updatedAt': DateTime.now().toUtc().toIso8601String(),
          'data': value,
        },
      };
      await repository.save(next, epoch, owner);
      if (mounted) setState(() => snapshots = next);
      return true;
    } catch (_) {
      if (mounted) setState(() => error = '更新沒有完成，顯示上次的資料');
      return false;
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  /// One refresh for the page: totals, then the records page on screen.
  /// Backing out of the first read skips the second.
  Future<void> refreshAll() async {
    final list = snapshots['list'];
    final page = list is Map && list['data'] is Map
        ? int.tryParse('${list['data']['page']}') ?? 1
        : 1;
    if (!await open(keyName: 'statistics') || !mounted) return;
    if (!await open(keyName: 'list', page: page) || !mounted) return;
    // What 學生請假修改 allows now: 撤回、修改、補檔.
    await open(keyName: 'actions');
  }

  List<LeaveActions> get actions {
    final cached = snapshots['actions'];
    return LeaveActions.fromSnapshot(cached is Map ? cached['data'] : null);
  }

  LeaveActions? actionsFor(String formNo) =>
      actions.where((a) => a.formNo == formNo && a.any).firstOrNull;

  /// 修改 or 補檔 in the school form; the records are read again afterwards.
  Future<void> edit(LeaveEntry entry) async {
    if (busy) return;
    setState(() => busy = true);
    bool? changed;
    try {
      changed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) =>
              LeaveApplicationScreen(session: session, leave: entry),
        ),
      );
    } finally {
      if (mounted) setState(() => busy = false);
    }
    if (changed == true && mounted && session.hasLocalAccount) {
      await refreshAll();
    }
  }

  Future<void> withdraw(String formNo, BuildContext detailContext) async {
    if (busy) return;
    final ok =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('撤回這張假單？'),
            content: Text('學校會刪除假單 $formNo，無法在 App 內復原。需要時請重新申請。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('保留假單'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: NiuColors.of(context).error,
                ),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('撤回假單'),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok || !mounted) return;
    setState(() => busy = true);
    bool? sent;
    try {
      sent = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => LeaveWithdrawScreen(session: session, formNo: formNo),
        ),
      );
    } finally {
      if (mounted) setState(() => busy = false);
    }
    if (sent == true && mounted && session.hasLocalAccount) {
      if (detailContext.mounted) Navigator.of(detailContext).pop();
      await refreshAll();
    }
  }

  Widget detail(
    Map<String, dynamic> record,
    StateSetter updateDetail,
    BuildContext detailContext,
  ) {
    final theme = Theme.of(context);
    final cached = snapshots['detail:${record['假單序號']}'];
    final data = cached is Map ? cached['data'] : null;
    final fields = data is Map && data['fields'] is Map
        ? Map<String, dynamic>.from(data['fields'] as Map)
        : <String, dynamic>{};
    final status = '${record['審核結果'] ?? '-'}';
    final id = '${record['假單序號']}';
    final workflow = data is Map && data['workflow'] is List
        ? data['workflow'] as List
        : null;
    final returnReason = workflow == null
        ? null
        : LeaveApprovalStep.returnReason(workflow);
    final workflowName = data is Map ? '${data['workflowName'] ?? ''}' : '';
    final periodEntries = data is Map && data['periods'] is List
        ? [
            for (final table in data['periods'] as List)
              ...leavePeriodEntries([
                for (final row in table as List)
                  [for (final cell in row as List) '$cell'],
              ]),
          ]
        : <LeavePeriodEntry>[];
    Future<void> update() async {
      await open(record: record);
      if (mounted && detailContext.mounted) updateDetail(() {});
    }

    // Like iOS, opening a record reads its 簽核流程 without asking: when it
    // was never read, or the records list has been refreshed since.
    final list = snapshots['list'];
    final listAt = list is Map
        ? DateTime.tryParse('${list['updatedAt']}')
        : null;
    final detailAt = cached is Map
        ? DateTime.tryParse('${cached['updatedAt']}')
        : null;
    final stale =
        workflow == null ||
        (listAt != null && detailAt != null && detailAt.isBefore(listAt));
    if (stale && !busy && _autoLoaded.add(id)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && detailContext.mounted) update();
      });
    }

    return NiuScrollPage(
      title: '請假明細',
      actions: [
        NiuIconButton(
          icon: NiuIcons.refresh,
          tooltip: '更新明細',
          onPressed: busy ? null : update,
        ),
      ],
      children: [
        if (returnReason != null) ...[
          NiuBanner(tone: NiuTone.error, message: '退回原因：$returnReason'),
          const SizedBox(height: NiuSpacing.lg),
        ],
        NiuCard(
          padding: const EdgeInsets.all(NiuSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              NiuBadge(label: status, tone: leaveStatusTone(status)),
              const SizedBox(height: NiuSpacing.sm),
              Text(
                '${record['請假類別'] ?? '-'}',
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: NiuSpacing.xs),
              Text(
                [
                  leaveRecordPeriodSummary(record),
                  '共 ${record['請假總節數'] ?? '-'} 節',
                ].where((v) => v.isNotEmpty).join('・'),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFeatures: tabularFigures,
                ),
              ),
            ],
          ),
        ),
        if (actionsFor(id) case final allowed?)
          NiuSection(
            title: '操作',
            subtitle: '修改與補檔會開啟學校的表單；撤回後學校會刪除這張假單。',
            child: NiuGroup(
              children: [
                if (allowed.modify)
                  NiuRow(
                    icon: Icons.edit_rounded,
                    hue: NiuHue.blue,
                    title: '修改假單',
                    subtitle: '更改假別、日期、節次或事由',
                    onTap: busy ? null : () => edit(LeaveEntry.modify(id)),
                  ),
                if (allowed.supplement)
                  NiuRow(
                    icon: NiuIcons.upload,
                    hue: NiuHue.cyan,
                    title: '補交證明文件',
                    subtitle: '只附加檔案，其他內容不變',
                    onTap: busy ? null : () => edit(LeaveEntry.supplement(id)),
                  ),
                if (allowed.withdraw)
                  NiuRow(
                    icon: Icons.undo_rounded,
                    hue: NiuHue.red,
                    title: '撤回假單',
                    subtitle: '學校會刪除這張假單',
                    onTap: busy ? null : () => withdraw(id, detailContext),
                  ),
              ],
            ),
          ),
        NiuSection(
          title: '申請內容',
          child: NiuCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                fact('申請日期', record['申請日期']),
                fact('假單序號', record['假單序號']),
                // The header card already shows type, dates and the count.
                for (final entry in fields.entries)
                  if (!const {
                    '申請日期',
                    '請假類別',
                    '請假日期',
                    '本次請假總節數',
                  }.contains(entry.key))
                    fact(entry.key, entry.value),
              ],
            ),
          ),
        ),
        if (periodEntries.isNotEmpty)
          NiuSection(
            title: '請假節次',
            child: NiuCard(child: LeavePeriodSchedule(entries: periodEntries)),
          ),
        NiuSection(
          title: '簽核流程',
          action: data is Map && data['workflowUpdatedAt'] != null
              ? RelativeUpdateText(
                  updatedAt: DateTime.tryParse('${data['workflowUpdatedAt']}'),
                  style: theme.textTheme.labelMedium,
                )
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (data is Map && data['workflowStale'] == true)
                const Padding(
                  padding: EdgeInsets.only(bottom: NiuSpacing.md),
                  child: NiuBanner(
                    tone: NiuTone.warning,
                    message: '這次沒有讀到最新流程，顯示上次的紀錄。',
                  ),
                ),
              if (workflow == null && busy)
                const NiuCard(child: NiuLoading(message: '正在讀取簽核流程'))
              else if (workflow == null)
                NiuCard(
                  child: NiuEmpty(
                    padding: const EdgeInsets.symmetric(
                      vertical: NiuSpacing.lg,
                    ),
                    icon: NiuIcons.pending,
                    title: '沒有讀到簽核流程',
                    message: '可以再試一次，或到校務系統的假單查看。',
                    action: FilledButton.tonal(
                      onPressed: busy ? null : update,
                      child: const Text('重新讀取'),
                    ),
                  ),
                )
              else if (workflow.isEmpty)
                const NiuCard(
                  child: NiuEmpty(
                    padding: EdgeInsets.symmetric(vertical: NiuSpacing.lg),
                    icon: NiuIcons.pending,
                    title: '還沒有簽核紀錄',
                    message: '學校尚未列出流程。',
                  ),
                )
              else
                LeaveWorkflow(steps: workflow),
              if (workflow != null && workflowName.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(
                    top: NiuSpacing.sm,
                    left: NiuSpacing.xs,
                  ),
                  child: Text(
                    '流程：$workflowName',
                    style: theme.textTheme.labelMedium,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget fact(String label, Object? value) =>
      NiuKeyValue(label: label, value: value == null ? '-' : '$value');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stats = snapshots['statistics'];
    final list = snapshots['list'];
    final periods =
        stats is Map && stats['data'] is Map && stats['data']['periods'] is Map
        ? Map<String, dynamic>.from(stats['data']['periods'] as Map)
        : <String, dynamic>{};
    final numbers = periods.values.map((v) => int.tryParse('$v')).toList();
    final total =
        numbers.isNotEmpty && numbers.every((n) => n != null && n >= 0)
        ? numbers.fold<int>(0, (sum, n) => sum + n!)
        : null;
    final records =
        list is Map && list['data'] is Map && list['data']['records'] is List
        ? list['data']['records'] as List
        : [];
    final page = list is Map ? int.tryParse('${list['data']['page']}') ?? 1 : 1;
    final pages = list is Map
        ? int.tryParse('${list['data']['pages']}') ?? 1
        : 1;
    if (loading) {
      return const NiuScrollPage(
        title: '請假',
        children: [NiuLoading(message: '正在讀取請假資料')],
      );
    }
    return NiuScrollPage(
      title: '請假',
      actions: [
        NiuIconButton(
          icon: NiuIcons.refresh,
          tooltip: '更新請假資料',
          onPressed: busy ? null : refreshAll,
        ),
      ],
      onRefresh: refreshAll,
      children: [
        if (error != null) ...[
          NiuBanner(tone: NiuTone.warning, message: error!),
          const SizedBox(height: NiuSpacing.lg),
        ],
        NiuCard(
          padding: const EdgeInsets.all(NiuSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: NiuStat(
                      label: '本學期累計請假',
                      value: '${total ?? '-'}',
                      unit: '節',
                      large: true,
                    ),
                  ),
                ],
              ),
              if (stats is Map) ...[
                const SizedBox(height: NiuSpacing.xs),
                NiuSyncStatus(
                  updatedAt: DateTime.tryParse('${stats['updatedAt']}'),
                ),
              ],
              if (periods.isNotEmpty) ...[
                const SizedBox(height: NiuSpacing.lg),
                LeaveTypeStatistics(periods: periods),
              ],
            ],
          ),
        ),
        const SizedBox(height: NiuSpacing.md),
        FilledButton.icon(
          onPressed: busy ? null : () => open(application: true),
          icon: const Icon(Icons.edit_calendar_rounded),
          label: const Text('申請請假'),
        ),
        NiuSection(
          title: '請假紀錄',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (list is Map)
                Padding(
                  padding: const EdgeInsets.only(
                    left: NiuSpacing.xs,
                    bottom: NiuSpacing.md,
                  ),
                  child: RelativeUpdateText(
                    style: theme.textTheme.labelMedium,
                    updatedAt: DateTime.tryParse('${list['updatedAt']}'),
                  ),
                ),
              if (records.isEmpty)
                NiuCard(
                  child: NiuEmpty(
                    padding: const EdgeInsets.symmetric(
                      vertical: NiuSpacing.lg,
                    ),
                    title: list == null ? '還沒有同步請假紀錄' : '沒有請假紀錄',
                    message: list == null
                        ? '更新後可以查看每筆假單的審核狀態。'
                        : '有新的假單時，更新一下就會出現。',
                    icon: NiuIcons.leave,
                    action: TextButton(
                      onPressed: busy ? null : () => open(keyName: 'list'),
                      child: const Text('更新紀錄'),
                    ),
                  ),
                ),
              for (final raw in records)
                Padding(
                  padding: const EdgeInsets.only(bottom: NiuSpacing.md),
                  child: NiuCard(
                    onTap: () {
                      final record = Map<String, dynamic>.from(raw);
                      record['_page'] = list['data']['page'];
                      _autoLoaded.remove('${record['假單序號']}');
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ListenableBuilder(
                            listenable: session,
                            builder: (_, _) => !session.hasLocalAccount
                                ? const Scaffold(
                                    body: Center(
                                      child: NiuEmpty(
                                        icon: NiuIcons.logout,
                                        title: '已登出',
                                      ),
                                    ),
                                  )
                                : StatefulBuilder(
                                    builder: (context, setDetailState) =>
                                        detail(record, setDetailState, context),
                                  ),
                          ),
                        ),
                      );
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        LeaveRecordContent(record: raw),
                        if (actionsFor('${(raw as Map)['假單序號']}')
                            case final allowed?)
                          Padding(
                            padding: const EdgeInsets.only(top: NiuSpacing.sm),
                            child: Text(
                              '可${[if (allowed.modify) '修改', if (allowed.supplement) '補檔', if (allowed.withdraw) '撤回'].join('、')}',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: NiuColors.of(context).accent,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              if (list is Map && pages > 1)
                Row(
                  children: [
                    TextButton(
                      onPressed: busy || page <= 1
                          ? null
                          : () => open(keyName: 'list', page: page - 1),
                      child: const Text('上一頁'),
                    ),
                    Expanded(
                      child: Text(
                        '$page / $pages',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontFeatures: tabularFigures,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: busy || page >= pages
                          ? null
                          : () => open(keyName: 'list', page: page + 1),
                      child: const Text('下一頁'),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}
