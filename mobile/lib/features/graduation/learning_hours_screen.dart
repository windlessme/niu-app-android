import 'package:flutter/material.dart';

import '../../core/analytics/app_analytics.dart';
import '../../core/session/campus_session.dart';
import '../../shared/shared.dart';
import 'learning_hours.dart';

/// 多元學習認證時數紀錄 from the student portal, which needs the campus
/// network. The last snapshot shows first and stays until a refresh loads.
class LearningHoursScreen extends StatefulWidget {
  const LearningHoursScreen({super.key, this.session, this.store});
  final CampusSession? session;
  final LearningHoursStore? store;

  @override
  State<LearningHoursScreen> createState() => _LearningHoursScreenState();
}

class _LearningHoursScreenState extends State<LearningHoursScreen> {
  late final session = widget.session ?? CampusSession.instance;
  late final store = widget.store ?? LearningHoursStore(session);
  LearningHoursSnapshot? snapshot;
  bool loading = true, refreshing = false;
  String? error;
  String? ability;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final cached = await store.cached();
    if (!mounted) return;
    setState(() {
      snapshot = cached;
      loading = false;
    });
    if (cached == null) await refresh();
  }

  Future<void> refresh() async {
    if (refreshing) return;
    setState(() {
      refreshing = true;
      error = null;
    });
    try {
      final fresh = await store.refresh();
      AppAnalytics.instance.result('learning_hours', true);
      if (!mounted || fresh == null) return;
      setState(() {
        snapshot = fresh;
        if (ability != null &&
            !fresh.records.any((r) => r.ability == ability)) {
          ability = null;
        }
      });
    } on LearningHoursException catch (failure) {
      AppAnalytics.instance.error('learning_hours', failure.reason);
      AppAnalytics.instance.result('learning_hours', false, {
        'reason': failure.reason,
      });
      if (mounted) setState(() => error = failure.message);
    } catch (_) {
      AppAnalytics.instance.error('learning_hours', 'unknown');
      AppAnalytics.instance.result('learning_hours', false, {
        'reason': 'unknown',
      });
      if (mounted) {
        setState(() => error = LearningHoursException.invalidResponse.message);
      }
    } finally {
      if (mounted) setState(() => refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = this.snapshot;
    if (snapshot == null) {
      return NiuScrollPage(
        title: '時數紀錄',
        children: [
          if (loading || refreshing)
            const NiuLoading(message: '正在讀取時數紀錄…\n首次讀取需連接校園網路')
          else
            NiuError(
              title: '無法讀取時數紀錄',
              message: error ?? LearningHoursException.invalidResponse.message,
              onRetry: refresh,
            ),
        ],
      );
    }
    final records = ability == null
        ? snapshot.records
        : snapshot.records.where((r) => r.ability == ability).toList();
    final theme = Theme.of(context);
    return NiuScrollPage(
      title: '時數紀錄',
      onRefresh: refresh,
      actions: [
        NiuIconButton(
          icon: NiuIcons.refresh,
          tooltip: '更新時數紀錄',
          onPressed: refreshing ? null : refresh,
        ),
      ],
      children: [
        if (snapshot.summaries.isNotEmpty) ...[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _AbilityChip(
                  title: '全部',
                  selected: ability == null,
                  onTap: () => setState(() => ability = null),
                ),
                for (final summary in snapshot.summaries) ...[
                  const SizedBox(width: NiuSpacing.sm),
                  _AbilityChip(
                    title: summary.ability,
                    detail:
                        '${formatLearningHours(summary.earned)} / '
                        '${formatLearningHours(summary.required)}',
                    selected: ability == summary.ability,
                    onTap: () => setState(() => ability = summary.ability),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: NiuSpacing.xl),
        ],
        NiuEyebrow('${ability ?? '全部'}・${records.length} 筆'),
        const SizedBox(height: NiuSpacing.sm),
        if (records.isEmpty)
          NiuCard(
            child: NiuEmpty(
              icon: NiuIcons.time,
              title: ability == null ? '尚無認證紀錄' : '此領域尚無認證紀錄',
              padding: const EdgeInsets.symmetric(vertical: NiuSpacing.xl),
            ),
          )
        else
          NiuGroup(
            insetDividers: NiuSpacing.lg,
            children: [for (final r in records) _RecordRow(record: r)],
          ),
        const SizedBox(height: NiuSpacing.xl),
        NiuSyncStatus(
          updatedAt: snapshot.fetchedAt,
          refreshing: refreshing,
          failed: error != null,
          onRetry: refresh,
        ),
        if (error != null) ...[
          const SizedBox(height: NiuSpacing.xs),
          Text(
            error!,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelMedium,
          ),
        ],
        const SizedBox(height: NiuSpacing.xs),
        Text(
          '更新時數紀錄需連接校園網路',
          textAlign: TextAlign.center,
          style: theme.textTheme.labelMedium,
        ),
      ],
    );
  }
}

class _AbilityChip extends StatelessWidget {
  const _AbilityChip({
    required this.title,
    required this.selected,
    required this.onTap,
    this.detail,
  });
  final String title;
  final String? detail;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = NiuColors.of(context);
    final text = Theme.of(context).textTheme;
    final foreground = selected ? colors.canvas : colors.ink;
    return Semantics(
      button: true,
      selected: selected,
      label: detail == null ? title : '$title，已認證 $detail 小時',
      excludeSemantics: true,
      child: Material(
        color: selected ? colors.ink : colors.fill,
        borderRadius: BorderRadius.circular(NiuRadius.control),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(NiuRadius.control),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: NiuSpacing.md,
                vertical: NiuSpacing.sm,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: text.titleSmall?.copyWith(color: foreground),
                  ),
                  if (detail != null)
                    Text(
                      detail!,
                      style: text.labelMedium?.copyWith(
                        color: selected
                            ? colors.canvas.withValues(alpha: 0.85)
                            : colors.inkSecondary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RecordRow extends StatelessWidget {
  const _RecordRow({required this.record});
  final LearningHoursRecord record;

  @override
  Widget build(BuildContext context) {
    final colors = NiuColors.of(context);
    final text = Theme.of(context).textTheme;
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.all(NiuSpacing.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(record.title, style: text.bodyLarge),
                  const SizedBox(height: NiuSpacing.xs),
                  Wrap(
                    spacing: NiuSpacing.sm,
                    runSpacing: NiuSpacing.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: colors.accentSoft,
                          borderRadius: BorderRadius.circular(NiuRadius.pill),
                        ),
                        child: Text(
                          record.ability,
                          style: text.labelMedium?.copyWith(
                            color: colors.accent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        record.dates,
                        style: text.labelMedium?.copyWith(
                          color: colors.inkSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: NiuSpacing.sm),
            Text(
              '${record.hours} 小時',
              style: text.titleSmall?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
