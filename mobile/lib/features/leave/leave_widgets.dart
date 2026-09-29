import 'package:flutter/material.dart';
import '../../shared/shared.dart';

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
        text: TextSpan(text: '期中、期末', style: text.bodySmall),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      final minimum = measure.width + NiuSpacing.lg;
      measure.dispose();
      final columns =
          ((constraints.maxWidth + NiuSpacing.lg) / (minimum + NiuSpacing.lg))
              .floor()
              .clamp(1, 2);
      final width =
          (constraints.maxWidth - (columns - 1) * NiuSpacing.lg) / columns;
      return Wrap(
        spacing: NiuSpacing.lg,
        runSpacing: NiuSpacing.sm,
        children: [
          for (final entry in periods.entries)
            SizedBox(
              width: width,
              child: Semantics(
                label: '${entry.key} ${entry.value} 節',
                excludeSemantics: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Tooltip(
                      message: entry.key,
                      child: Text(
                        entry.key,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodySmall?.copyWith(
                          color: colors.secondary,
                        ),
                      ),
                    ),
                    const SizedBox(height: NiuSpacing.xs),
                    Text(
                      '${entry.value}',
                      style: text.titleMedium?.copyWith(
                        color: (int.tryParse('${entry.value}') ?? 0) > 0
                            ? colors.accent
                            : colors.secondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    },
  );
}

class LeaveRecordContent extends StatelessWidget {
  const LeaveRecordContent({super.key, required this.record});
  final Map record;
  @override
  Widget build(BuildContext context) {
    final status = '${record['審核結果'] ?? '-'}';
    final tone = switch (status.trim()) {
      '已核准' || '核准' => NiuStatusTone.success,
      '審核中' || '簽核中' => NiuStatusTone.warning,
      '退回' || '不核准' => NiuStatusTone.error,
      _ => NiuStatusTone.neutral,
    };
    final text = Theme.of(context).textTheme;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${record['請假類別'] ?? '-'}', style: text.titleMedium),
              const SizedBox(height: NiuSpacing.sm),
              Text(
                '${record['請假起日'] ?? '-'}–${record['請假訖日'] ?? '-'}',
                style: text.bodyMedium,
              ),
              Text('${record['請假總節數'] ?? '-'} 節', style: text.bodySmall),
              const SizedBox(height: NiuSpacing.sm),
              NiuStatusChip(label: status, tone: tone),
              if ('${record['請假事由'] ?? ''}'.trim().isNotEmpty) ...[
                const SizedBox(height: NiuSpacing.sm),
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
            Icons.chevron_right,
            color: NiuColors.of(context).secondary,
          ),
        ),
      ],
    );
  }
}
