import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/demo/demo_data.dart';
import '../../core/session/campus_session.dart';
import '../../core/web/academic_portal_screen.dart';
import '../../shared/shared.dart';
import 'leave_repository.dart';
import 'leave_widgets.dart';
import 'leave_application_screen.dart';

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
                : keyName == 'statistics'
                ? '請假統計'
                : record != null
                ? '請假明細'
                : '請假紀錄',
            session: session,
            navigationScript: leaveMenuNavigation(
              application || keyName == 'statistics',
              agreeForStatistics: keyName == 'statistics',
            ),
            extractScript: application
                ? null
                : keyName == 'statistics'
                ? leaveStatisticsExtract
                : record != null
                ? leaveDetailWithWorkflowExtract()
                : leaveInFrames(leaveListExtract),
            prepareScript: application || keyName == 'statistics'
                ? null
                : record != null
                ? leaveDetailPrepare(
                    '${record['假單序號']}',
                    int.tryParse('${record['_page']}') ?? 1,
                  )
                : leaveInFrames(leavePagePrepare(page)),
            demoSnapshot: () => keyName == 'statistics'
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
    await open(keyName: 'list', page: page);
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
    Future<void> update() async {
      await open(record: record);
      if (mounted && detailContext.mounted) updateDetail(() {});
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
                '${record['請假起日'] ?? '-'} – ${record['請假訖日'] ?? '-'} · ${record['請假總節數'] ?? '-'} 節',
                style: theme.textTheme.bodySmall,
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
                for (final key in [
                  '申請日期',
                  '請假起日',
                  '請假訖日',
                  '起始節次',
                  '迄止節次',
                  '請假總節數',
                ])
                  fact(key, record[key]),
                for (final entry in fields.entries)
                  fact(entry.key, entry.value),
                if (data is Map && data['periods'] is List)
                  for (final table in data['periods'] as List)
                    for (final row in table as List)
                      Padding(
                        padding: const EdgeInsets.only(top: NiuSpacing.xs),
                        child: Text(
                          (row as List).join(' · '),
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
              ],
            ),
          ),
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
              if (data is! Map || data['workflow'] is! List)
                NiuCard(
                  child: NiuEmpty(
                    padding: const EdgeInsets.symmetric(
                      vertical: NiuSpacing.lg,
                    ),
                    icon: NiuIcons.pending,
                    title: '還沒有讀取簽核流程',
                    message: '更新明細後就會顯示。',
                    action: FilledButton.tonal(
                      onPressed: busy ? null : update,
                      child: const Text('更新明細'),
                    ),
                  ),
                )
              else if ((data['workflow'] as List).isEmpty)
                const NiuCard(
                  child: NiuEmpty(
                    padding: EdgeInsets.symmetric(vertical: NiuSpacing.lg),
                    icon: NiuIcons.pending,
                    title: '還沒有簽核紀錄',
                    message: '學校尚未列出流程。',
                  ),
                )
              else
                LeaveWorkflow(steps: data['workflow'] as List),
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
                      final record = Map<String, dynamic>.from(raw as Map);
                      record['_page'] = list['data']['page'];
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
                    child: LeaveRecordContent(record: raw),
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
