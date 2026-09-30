import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/session/campus_session.dart';
import '../../core/web/academic_portal_screen.dart';
import '../../shared/shared.dart';
import '../../shared/app_fact.dart';
import 'leave_repository.dart';
import 'leave_widgets.dart';

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
      if (mounted) setState(() => error = '無法讀取快取');
    } finally {
      if (mounted) setState(() => loading = false);
    }
    if (mounted && snapshots.isEmpty && error == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
        await open(keyName: 'statistics');
        if (!mounted || !snapshots.containsKey('statistics')) return;
        await open(keyName: 'list');
      });
    }
  }

  @override
  void dispose() {
    session.removeListener(changed);
    unawaited(repository.dispose());
    super.dispose();
  }

  Future<void> open({
    String? keyName,
    Map<String, dynamic>? record,
    bool application = false,
    int page = 1,
  }) async {
    if (busy || !session.hasLocalAccount) return;
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
                ? '請假申請'
                : keyName == 'statistics'
                ? '本學期統計'
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
            onSnapshot: (value, _) async {
              if (context.mounted) {
                Navigator.pop(context, Map<String, dynamic>.from(value as Map));
              }
            },
          ),
        ),
      );
      if (value == null) return;
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
    } catch (_) {
      if (mounted) setState(() => error = '更新未完成');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget detail(
    Map<String, dynamic> record,
    StateSetter updateDetail,
    BuildContext detailContext,
  ) {
    final cached = snapshots['detail:${record['假單序號']}'];
    final data = cached is Map ? cached['data'] : null;
    final fields = data is Map && data['fields'] is Map
        ? Map<String, dynamic>.from(data['fields'] as Map)
        : <String, dynamic>{};
    return Scaffold(
      appBar: const IosPageHeader(title: '請假明細'),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(NiuSpacing.xl),
          children: [
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final key in [
                    '請假類別',
                    '審核結果',
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
                        Text((row as List).join(' · ')),
                ],
              ),
            ),
            TextButton(
              onPressed: busy
                  ? null
                  : () async {
                      await open(record: record);
                      if (mounted && detailContext.mounted) updateDetail(() {});
                    },
              child: const Text('更新明細'),
            ),
            const SectionHeader(title: '簽核流程'),
            if (data is Map && data['workflowUpdatedAt'] != null)
              RelativeUpdateText(
                updatedAt: DateTime.tryParse('${data['workflowUpdatedAt']}'),
              ),
            if (data is Map && data['workflowStale'] == true)
              const Text('流程尚未更新'),
            if (data is! Map || data['workflow'] is! List)
              const NiuEmptyState(title: '尚未讀取簽核流程', message: '更新明細即可讀取。'),
            if (data is Map && data['workflow'] is List) ...[
              if ((data['workflow'] as List).isEmpty)
                const NiuEmptyState(title: '目前沒有簽核紀錄', message: '校方尚未列出流程紀錄。'),
              for (final step in data['workflow'] as List)
                Padding(
                  padding: const EdgeInsets.only(bottom: NiuSpacing.md),
                  child: AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${step['關卡說明'] ?? '-'}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: NiuSpacing.sm),
                        for (final key in ['簽核狀況', '簽核日期', '簽核單位'])
                          fact(key, step[key]),
                      ],
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget fact(String label, Object? value) =>
      AppFact(label: label, value: value == null ? '-' : '$value');

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final bottomInset = [
      media.padding.bottom,
      media.viewPadding.bottom,
      media.systemGestureInsets.bottom,
    ].reduce((a, b) => a > b ? a : b);
    final metadataStyle = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: NiuColors.of(context).tertiary);
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
    return Scaffold(
      appBar: const IosPageHeader(title: '學生請假'),
      body: SafeArea(
        top: false,
        bottom: false,
        maintainBottomViewPadding: true,
        child: loading
            ? const AppLoadingState()
            : ListView(
                padding: EdgeInsets.fromLTRB(
                  NiuSpacing.xl,
                  NiuSpacing.xl,
                  NiuSpacing.xl,
                  NiuSpacing.xxl + bottomInset,
                ),
                children: [
                  FilledButton.icon(
                    onPressed: busy ? null : () => open(application: true),
                    icon: const Icon(Icons.edit_calendar_outlined),
                    label: const Text('申請請假'),
                  ),
                  if (error != null) Text(error!),
                  const SectionHeader(title: '本學期請假'),
                  HeroCard(
                    padding: const EdgeInsets.all(NiuSpacing.xl),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${total ?? '-'} 節',
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: NiuSpacing.xs),
                        Text(
                          '本學期累計請假',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: NiuColors.of(context).secondary,
                              ),
                        ),
                        const SizedBox(height: NiuSpacing.sm),
                        if (stats is Map)
                          RelativeUpdateText(
                            style: metadataStyle,
                            updatedAt: DateTime.tryParse(
                              '${stats['updatedAt']}',
                            ),
                          ),
                        const SizedBox(height: NiuSpacing.md),
                        LeaveTypeStatistics(periods: periods),
                        const SizedBox(height: NiuSpacing.sm),
                        TextButton.icon(
                          onPressed: busy
                              ? null
                              : () => open(keyName: 'statistics'),
                          icon: const Icon(Icons.refresh),
                          label: const Text('更新統計'),
                        ),
                      ],
                    ),
                  ),
                  SectionHeader(
                    title: '請假紀錄',
                    crossAxisAlignment: CrossAxisAlignment.center,
                    trailing: TextButton(
                      onPressed: busy ? null : () => open(keyName: 'list'),
                      child: const Text('更新'),
                    ),
                  ),
                  if (list is Map) ...[
                    RelativeUpdateText(
                      style: metadataStyle,
                      updatedAt: DateTime.tryParse('${list['updatedAt']}'),
                    ),
                    Text(
                      '第 ${list['data']['page']}／${list['data']['pages']} 頁',
                      style: metadataStyle,
                    ),
                    Wrap(
                      children: [
                        TextButton(
                          onPressed:
                              busy ||
                                  (int.tryParse('${list['data']['page']}') ??
                                          1) <=
                                      1
                              ? null
                              : () => open(
                                  keyName: 'list',
                                  page:
                                      int.parse('${list['data']['page']}') - 1,
                                ),
                          child: const Text('上一頁'),
                        ),
                        TextButton(
                          onPressed:
                              busy ||
                                  (int.tryParse('${list['data']['page']}') ??
                                          1) >=
                                      (int.tryParse(
                                            '${list['data']['pages']}',
                                          ) ??
                                          1)
                              ? null
                              : () => open(
                                  keyName: 'list',
                                  page:
                                      int.parse('${list['data']['page']}') + 1,
                                ),
                          child: const Text('下一頁'),
                        ),
                      ],
                    ),
                  ],
                  if (records.isEmpty)
                    NiuEmptyState(
                      title: list == null ? '尚未同步請假紀錄' : '目前沒有請假紀錄',
                      message: list == null ? '更新後即可查看請假申請與狀態。' : '可更新查看最新紀錄。',
                      icon: Icons.event_note_outlined,
                      action: TextButton(
                        onPressed: busy ? null : () => open(keyName: 'list'),
                        child: const Text('更新紀錄'),
                      ),
                    ),
                  for (final raw in records)
                    Padding(
                      padding: const EdgeInsets.only(bottom: NiuSpacing.md),
                      child: AppCard(
                        onTap: () {
                          final record = Map<String, dynamic>.from(raw as Map);
                          record['_page'] = list['data']['page'];
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ListenableBuilder(
                                listenable: session,
                                builder: (_, _) => !session.hasLocalAccount
                                    ? const Scaffold(
                                        body: Center(child: Text('已登出')),
                                      )
                                    : StatefulBuilder(
                                        builder: (context, setDetailState) =>
                                            detail(
                                              record,
                                              setDetailState,
                                              context,
                                            ),
                                      ),
                              ),
                            ),
                          );
                        },
                        child: LeaveRecordContent(record: raw),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
