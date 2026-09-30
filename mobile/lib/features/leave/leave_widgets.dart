import 'package:flutter/material.dart';
import '../../shared/shared.dart';

/// Per-type period counts as a compact tile grid.
class LeaveTypeStatistics extends StatelessWidget {
  const LeaveTypeStatistics({super.key, required this.periods});
  final Map<String, dynamic> periods;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final text = Theme.of(context).textTheme;
      final colors = NiuColors.of(context);
      // Measure a readable label width using the actual theme and text scale.
      final measure = TextPainter(
        text: TextSpan(text: '期中、期末', style: text.labelMedium),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      final minimum = measure.width + NiuSpacing.xxl;
      measure.dispose();
      const gap = NiuSpacing.sm;
      final columns = ((constraints.maxWidth + gap) / (minimum + gap))
          .floor()
          .clamp(1, 3);
      final width = (constraints.maxWidth - (columns - 1) * gap) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final entry in periods.entries)
            SizedBox(
              width: width,
              child: Semantics(
                label: '${entry.key} ${entry.value} 節',
                excludeSemantics: true,
                child: NiuWell(
                  padding: const EdgeInsets.symmetric(
                    horizontal: NiuSpacing.md,
                    vertical: 10,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Tooltip(
                        message: entry.key,
                        child: Text(
                          entry.key,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: text.labelMedium,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${entry.value}',
                        style: text.titleLarge?.copyWith(
                          fontFeatures: tabularFigures,
                          color: (int.tryParse('${entry.value}') ?? 0) > 0
                              ? colors.ink
                              : colors.inkTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}

NiuTone leaveStatusTone(String status) => switch (status.trim()) {
  '已核准' || '核准' => NiuTone.success,
  '審核中' || '簽核中' => NiuTone.warning,
  '退回' || '不核准' => NiuTone.error,
  _ => NiuTone.neutral,
};

class LeaveRecordContent extends StatelessWidget {
  const LeaveRecordContent({super.key, required this.record});
  final Map record;
  @override
  Widget build(BuildContext context) {
    final status = '${record['審核結果'] ?? '-'}';
    final text = Theme.of(context).textTheme;
    final start = '${record['請假起日'] ?? '-'}';
    final end = '${record['請假訖日'] ?? '-'}';
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${record['請假類別'] ?? '-'}',
                      style: text.titleMedium,
                    ),
                  ),
                  const SizedBox(width: NiuSpacing.sm),
                  NiuBadge(label: status, tone: leaveStatusTone(status)),
                ],
              ),
              const SizedBox(height: NiuSpacing.xs),
              Text(
                '${start == end ? start : '$start – $end'} · ${record['請假總節數'] ?? '-'} 節',
                style: text.bodySmall?.copyWith(fontFeatures: tabularFigures),
              ),
              if ('${record['請假事由'] ?? ''}'.trim().isNotEmpty) ...[
                const SizedBox(height: NiuSpacing.xs),
                Text(
                  '${record['請假事由']}',
                  style: text.bodySmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: NiuSpacing.sm),
        ExcludeSemantics(
          child: Icon(
            NiuIcons.forward,
            color: NiuColors.of(context).inkTertiary,
          ),
        ),
      ],
    );
  }
}

/// Vertical approval timeline.
class LeaveWorkflow extends StatelessWidget {
  const LeaveWorkflow({super.key, required this.steps});
  final List steps;
  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = NiuColors.of(context);
    return NiuCard(
      child: Column(
        children: [
          for (final (i, step) in steps.indexed)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 20,
                    child: Column(
                      children: [
                        Container(
                          margin: const EdgeInsets.only(top: 4),
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: leaveStatusTone(
                              '${step['簽核狀況'] ?? ''}',
                            ).foreground(context),
                          ),
                        ),
                        if (i < steps.length - 1)
                          Expanded(
                            child: Container(
                              width: 2,
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              color: colors.hairline,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: NiuSpacing.md),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                        bottom: i < steps.length - 1 ? NiuSpacing.lg : 0,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${step['關卡說明'] ?? '-'}',
                            style: text.titleSmall,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            [
                              '${step['簽核狀況'] ?? '-'}',
                              if ('${step['簽核單位'] ?? ''}'.trim().isNotEmpty)
                                '${step['簽核單位']}',
                              if ('${step['簽核日期'] ?? ''}'.trim().isNotEmpty)
                                '${step['簽核日期']}',
                            ].join(' · '),
                            style: text.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
