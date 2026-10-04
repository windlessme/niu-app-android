import 'package:flutter/material.dart';
import '../../shared/shared.dart';
import 'leave_application_data.dart';

/// School period choices grouped by date, with per-day select all.
class LeavePeriodSheet extends StatefulWidget {
  const LeavePeriodSheet({super.key, required this.available});
  final List<LeavePeriodChoice> available;
  @override
  State<LeavePeriodSheet> createState() => _LeavePeriodSheetState();
}

class _LeavePeriodSheetState extends State<LeavePeriodSheet> {
  late final chosen = <String>{
    for (final p in widget.available)
      if (p.selected) p.value,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = NiuColors.of(context);
    final byDate = <String, List<LeavePeriodChoice>>{};
    for (final p in widget.available) {
      byDate.putIfAbsent(p.date, () => []).add(p);
    }
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              NiuSpacing.gutter,
              0,
              NiuSpacing.gutter,
              NiuSpacing.sm,
            ),
            child: Text('選擇請假節次', style: theme.textTheme.titleLarge),
          ),
          Flexible(
            child: widget.available.isEmpty
                ? const NiuEmpty(
                    icon: NiuIcons.time,
                    title: '這段日期沒有可選的節次',
                    message: '換個日期，或到學校網頁確認。',
                  )
                : ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(
                      horizontal: NiuSpacing.gutter,
                    ),
                    children: [
                      for (final entry in byDate.entries) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            NiuSpacing.xs,
                            NiuSpacing.md,
                            0,
                            NiuSpacing.xs,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  displayLeaveDate(entry.key),
                                  style: theme.textTheme.titleSmall,
                                ),
                              ),
                              TextButton(
                                onPressed: () => setState(() {
                                  final values = entry.value.map(
                                    (p) => p.value,
                                  );
                                  values.every(chosen.contains)
                                      ? chosen.removeAll(values)
                                      : chosen.addAll(values);
                                }),
                                child: Text(
                                  entry.value
                                          .map((p) => p.value)
                                          .every(chosen.contains)
                                      ? '取消全選'
                                      : '全選',
                                ),
                              ),
                            ],
                          ),
                        ),
                        NiuGroup(
                          insetDividers: NiuSpacing.lg,
                          children: [
                            for (final p in entry.value)
                              NiuRow(
                                title: p.period,
                                subtitle: p.course.isEmpty ? null : p.course,
                                chevron: false,
                                onTap: () => setState(
                                  () => chosen.contains(p.value)
                                      ? chosen.remove(p.value)
                                      : chosen.add(p.value),
                                ),
                                trailing: Icon(
                                  chosen.contains(p.value)
                                      ? Icons.check_circle_rounded
                                      : Icons.radio_button_unchecked_rounded,
                                  color: chosen.contains(p.value)
                                      ? colors.accent
                                      : colors.inkTertiary,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(NiuSpacing.gutter),
            child: FilledButton(
              onPressed: chosen.isEmpty
                  ? null
                  : () => Navigator.pop(context, chosen.toList()),
              child: Text(chosen.isEmpty ? '確認節次' : '確認節次（${chosen.length} 節）'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Summary shown before the one-time submission.
class LeaveSubmitSheet extends StatelessWidget {
  const LeaveSubmitSheet({super.key, required this.data, required this.reason});
  final LeaveApplicationData data;
  final String reason;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          NiuSpacing.gutter,
          0,
          NiuSpacing.gutter,
          NiuSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('確認送出請假', style: theme.textTheme.titleLarge),
            const SizedBox(height: NiuSpacing.lg),
            NiuCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  NiuKeyValue(label: '假別', value: data.typeLabel),
                  NiuKeyValue(
                    label: '日期',
                    value: data.start == data.end
                        ? displayLeaveDate(data.start)
                        : '${displayLeaveDate(data.start)} – ${displayLeaveDate(data.end)}',
                  ),
                  NiuKeyValue(label: '節次', value: '${data.total ?? '-'} 節'),
                  const Divider(height: NiuSpacing.xl),
                  Text('事由', style: theme.textTheme.labelMedium),
                  const SizedBox(height: NiuSpacing.xs),
                  Text(reason, style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
            const SizedBox(height: NiuSpacing.md),
            const NiuBanner(
              tone: NiuTone.neutral,
              message: '送出後會進入學校審核，無法在 App 內撤回。',
            ),
            const SizedBox(height: NiuSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: NiuSpacing.md),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('送出申請'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact 日期 value: `10/1（四）` or `10/1（四）– 10/2（五）・2 天`.
String leaveRangeSummary(String start, String end) {
  final from = parseSchoolLeaveDate(start), to = parseSchoolLeaveDate(end);
  if (from == null || to == null || to.isBefore(from)) {
    return '${displayLeaveDate(start)} – ${displayLeaveDate(end)}';
  }
  String day(DateTime d) => '${d.month}/${d.day}（${'一二三四五六日'[d.weekday - 1]}）';
  if (from == to) return day(from);
  return '${day(from)} – ${day(to)}・${to.difference(from).inDays + 1} 天';
}
