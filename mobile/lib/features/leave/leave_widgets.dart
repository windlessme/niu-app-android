import 'package:flutter/material.dart';
import '../../shared/shared.dart';

/// The school's type name without its parenthesised sub-types, e.g.
/// 「產假（產前假／陪產假／流產假／哺乳假）」 reads 「產假」.
String leaveTypeShortName(String name) {
  final cut = name.indexOf(RegExp(r'[(（]'));
  final short = (cut > 0 ? name.substring(0, cut) : name).trim();
  return short.isEmpty ? name.trim() : short;
}

/// Per-type period counts. Types the student used are tiles of equal height
/// whose rows always fill the width; the zero types share one quiet line.
class LeaveTypeStatistics extends StatelessWidget {
  const LeaveTypeStatistics({super.key, required this.periods});
  final Map<String, dynamic> periods;

  static int? _count(Object? value) => int.tryParse('$value'.trim());

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = NiuColors.of(context);
    final used = [
      for (final e in periods.entries)
        if ((_count(e.value) ?? 1) != 0) e,
    ];
    final unused = [
      for (final e in periods.entries)
        if (_count(e.value) == 0) leaveTypeShortName(e.key),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (used.isNotEmpty) _grid(context, used),
        if (used.isNotEmpty && unused.isNotEmpty)
          const SizedBox(height: NiuSpacing.md),
        if (unused.isNotEmpty)
          Semantics(
            label: '${unused.join('、')}，都是 0 節',
            excludeSemantics: true,
            child: Text(
              used.isEmpty
                  ? '各假別都是 0 節：${unused.join('、')}'
                  : '${unused.join('、')}：0 節',
              style: text.bodySmall?.copyWith(color: colors.inkTertiary),
            ),
          ),
      ],
    );
  }

  Widget _grid(BuildContext context, List<MapEntry<String, dynamic>> used) =>
      LayoutBuilder(
        builder: (context, constraints) {
          final text = Theme.of(context).textTheme;
          // The widest column count whose tiles still fit 「身心調適假」.
          final measure = TextPainter(
            text: TextSpan(text: '身心調適假', style: text.labelMedium),
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
          )..layout();
          final minimum = measure.width + NiuSpacing.xxl;
          measure.dispose();
          const gap = NiuSpacing.sm;
          final fit = ((constraints.maxWidth + gap) / (minimum + gap))
              .floor()
              .clamp(1, 3);
          // Prefer an even split: 4 types as 2 × 2 rather than 3 + 1.
          final columns = used.length <= fit
              ? used.length
              : used.length == 4 && fit >= 2
              ? 2
              : fit;
          final rows = [
            for (var i = 0; i < used.length; i += columns)
              used.sublist(i, (i + columns).clamp(0, used.length)),
          ];
          return Column(
            children: [
              for (final (i, row) in rows.indexed) ...[
                if (i > 0) const SizedBox(height: gap),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final (j, entry) in row.indexed) ...[
                        if (j > 0) const SizedBox(width: gap),
                        Expanded(child: _tile(context, entry)),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      );

  Widget _tile(BuildContext context, MapEntry<String, dynamic> entry) {
    final text = Theme.of(context).textTheme;
    final name = leaveTypeShortName(entry.key);
    return Semantics(
      label: '${entry.key} ${entry.value} 節',
      excludeSemantics: true,
      child: Tooltip(
        message: entry.key,
        child: NiuWell(
          padding: const EdgeInsets.symmetric(
            horizontal: NiuSpacing.md,
            vertical: 10,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.labelMedium,
              ),
              const SizedBox(height: 2),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: '${entry.value}'),
                    TextSpan(text: ' 節', style: text.labelMedium),
                  ],
                ),
                style: text.titleLarge?.copyWith(fontFeatures: tabularFigures),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Matches the school's wording loosely: 「已核准」「退回修改」「簽核中」….
NiuTone leaveStatusTone(String status) {
  final s = status.trim();
  if (s.contains('不核准')) return NiuTone.error;
  if (s.contains('退回')) return NiuTone.error;
  if (s.contains('核准') || s.contains('結案') || s.contains('已簽核')) {
    return NiuTone.success;
  }
  if (s.contains('審核') || s.contains('簽核') || s.contains('申請')) {
    return NiuTone.warning;
  }
  return NiuTone.neutral;
}

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

/// One stage of the school's 簽核流程 (FLO3020_01 / FLO3040_01).
class LeaveApprovalStep {
  LeaveApprovalStep(Map step)
    : status = _field(step, '簽核狀況'),
      date = _field(step, '簽核日期'),
      stage = _field(step, '關卡說明'),
      unit = _field(step, '簽核單位'),
      person = _field(step, '簽核人'),
      comment = _field(step, '簽核意見');
  final String status, date, stage, unit, person, comment;

  static String _field(Map step, String key) => '${step[key] ?? ''}'.trim();

  bool get isReturned => status.contains('退回');
  bool get isDone =>
      !isReturned &&
      (status.contains('已簽核') ||
          status.contains('核准') ||
          status.contains('結案'));
  bool get isCurrent => !isDone && !isReturned && status.contains('簽核中');

  /// The school fills these in by itself; they say nothing beyond the status.
  bool get hasMeaningfulComment =>
      comment.isNotEmpty &&
      !const {'(已簽核，查無簽核意見。)', '(申請送出)', '(自動歸檔)'}.contains(comment);

  /// Why the form came back: the newest 退回 comment, as iOS shows it.
  static String? returnReason(List steps) {
    for (final step in steps.reversed) {
      if (step is! Map) continue;
      final s = LeaveApprovalStep(step);
      if (s.isReturned && s.hasMeaningfulComment) return s.comment;
    }
    return null;
  }
}

/// 簽核流程 as a vertical timeline: who signed, when, and what they said.
class LeaveWorkflow extends StatelessWidget {
  const LeaveWorkflow({super.key, required this.steps});
  final List steps;
  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = NiuColors.of(context);
    final items = [
      for (final s in steps)
        if (s is Map) LeaveApprovalStep(s),
    ];
    return NiuCard(
      child: Column(
        children: [
          for (final (i, step) in items.indexed)
            Semantics(
              label: [
                '第 ${i + 1} 關',
                step.stage.isEmpty ? '簽核' : step.stage,
                step.status,
                if ('${step.unit} ${step.person}'.trim().isNotEmpty)
                  '${step.unit} ${step.person}'.trim(),
                if (step.date.isNotEmpty) step.date,
                if (step.hasMeaningfulComment) '意見：${step.comment}',
              ].join('，'),
              excludeSemantics: true,
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 22,
                      child: Column(
                        children: [
                          _marker(context, step),
                          if (i < items.length - 1)
                            Expanded(
                              child: Container(
                                width: 2,
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                color: step.isDone
                                    ? colors.success
                                    : colors.hairline,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: NiuSpacing.md),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(
                          bottom: i < items.length - 1 ? NiuSpacing.lg : 0,
                        ),
                        child: _content(context, step, text, colors),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _marker(BuildContext context, LeaveApprovalStep step) {
    final colors = NiuColors.of(context);
    final (icon, color) = step.isReturned
        ? (Icons.undo_rounded, colors.error)
        : step.isDone
        ? (NiuIcons.success, colors.success)
        : step.isCurrent
        ? (NiuIcons.time, colors.warning)
        : (NiuIcons.neutral, colors.inkTertiary);
    return Icon(icon, size: 22, color: color);
  }

  Widget _content(
    BuildContext context,
    LeaveApprovalStep step,
    TextTheme text,
    NiuColors colors,
  ) {
    final pending = !step.isDone && !step.isReturned && !step.isCurrent;
    final who = [step.unit, step.person].where((v) => v.isNotEmpty).join(' ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: NiuSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              step.stage.isEmpty ? '簽核' : step.stage,
              style: text.titleSmall?.copyWith(
                color: pending ? colors.inkSecondary : colors.ink,
              ),
            ),
            if (step.status.isNotEmpty)
              Text(
                step.status,
                style: text.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: leaveStatusTone(step.status) == NiuTone.neutral
                      ? colors.inkTertiary
                      : leaveStatusTone(step.status).foreground(context),
                ),
              ),
          ],
        ),
        if (who.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(who, style: text.bodySmall),
        ],
        if (step.date.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            step.date,
            style: text.bodySmall?.copyWith(
              fontFeatures: tabularFigures,
              color: colors.inkTertiary,
            ),
          ),
        ],
        if (step.hasMeaningfulComment) ...[
          const SizedBox(height: NiuSpacing.xs),
          Text(
            step.comment,
            style: text.bodyMedium?.copyWith(
              color: step.isReturned ? colors.error : colors.ink,
            ),
          ),
        ],
      ],
    );
  }
}
