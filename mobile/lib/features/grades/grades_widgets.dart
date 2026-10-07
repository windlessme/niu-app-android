import 'package:flutter/material.dart';
import '../../shared/shared.dart';
import 'grade_statistics.dart';
import 'grades_models.dart';

/// `3` → `3`, `2.5` → `2.5`.
String _credits(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

String _percent(double? v) => v == null ? '—' : '${(v * 100).round()}%';

/// GPA overview: headline value, progress to 4.3, supporting totals and,
/// across several terms, the GPA trend.
class GradeSummaryCard extends StatelessWidget {
  const GradeSummaryCard({
    super.key,
    required this.stats,
    required this.title,
    this.trend = const [],
  });
  final GradeStatistics stats;
  final String title;

  /// Terms oldest first; drawn when there are at least two with a GPA.
  final List<GradeSemester> trend;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final points = [
      for (final s in trend)
        if (s.stats.gpa != null) (s.shortLabel, s.stats.gpa!),
    ];
    return NiuCard(
      padding: const EdgeInsets.all(NiuSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: NiuStat(
                  label: title,
                  value: stats.gpa?.toStringAsFixed(2) ?? '—',
                  unit: '/ 4.30',
                  large: true,
                ),
              ),
              IconButton(
                tooltip: 'GPA 怎麼算',
                icon: const Icon(Icons.info_outline_rounded),
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => const GpaExplanation(),
                ),
              ),
            ],
          ),
          const SizedBox(height: NiuSpacing.md),
          NiuProgressBar(value: (stats.gpa ?? 0) / 4.3, semanticLabel: title),
          const SizedBox(height: NiuSpacing.lg),
          Row(
            children: [
              Expanded(
                child: NiuStat(
                  label: '平均分數',
                  value: stats.average?.toStringAsFixed(1) ?? '—',
                ),
              ),
              Expanded(
                child: NiuStat(label: '通過率', value: _percent(stats.passRate)),
              ),
              Expanded(
                child: NiuStat(
                  label: '實得學分',
                  value: _credits(stats.earnedCredits),
                  unit: '/ ${_credits(stats.attemptedCredits)}',
                ),
              ),
            ],
          ),
          if (points.length >= 2) ...[
            const SizedBox(height: NiuSpacing.xl),
            Text('GPA 走勢', style: theme.textTheme.labelMedium),
            const SizedBox(height: NiuSpacing.sm),
            GradeTrendChart(points: points),
          ],
          const SizedBox(height: NiuSpacing.lg),
          Text(
            '依數字成績估算；通過、抵免等文字成績不計入 GPA，但計入實得學分。正式結果以學校為準。',
            style: theme.textTheme.labelMedium,
          ),
        ],
      ),
    );
  }
}

/// How the app estimates GPA: the school doesn't publish one.
class GpaExplanation extends StatelessWidget {
  const GpaExplanation({super.key});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final figures = theme.textTheme.bodyMedium?.copyWith(
      fontFeatures: tabularFigures,
    );
    return AlertDialog(
      title: const Text('GPA 怎麼算'),
      scrollable: true,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '學校沒有提供 GPA，這裡由 App 依分數換算 4.3 制績分，僅供參考。\n\n'
            'GPA ＝ Σ（績分 × 學分）÷ Σ 學分\n\n'
            '只計入有數字成績且學分大於 0 的課程；通過、抵免等文字成績不計入。'
            '例如 85 分 3 學分、72 分 2 學分：(4.0×3 + 2.7×2) ÷ 5 = 3.48。',
          ),
          const SizedBox(height: NiuSpacing.lg),
          for (final (range, letter, points) in GradeStatistics.bands)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Expanded(child: Text(range, style: figures)),
                  Expanded(child: Text(letter, style: figures)),
                  Text(points.toStringAsFixed(1), style: figures),
                ],
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('知道了'),
        ),
      ],
    );
  }
}

/// Line of term GPAs, oldest on the left, each point labelled with its value.
class GradeTrendChart extends StatelessWidget {
  const GradeTrendChart({super.key, required this.points});
  final List<(String, double)> points;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = NiuColors.of(context);
    final labelStyle = theme.textTheme.labelSmall?.copyWith(
      color: colors.inkSecondary,
      fontFeatures: tabularFigures,
    );
    return Semantics(
      label:
          'GPA 走勢：${points.map((p) => '${p.$1} ${p.$2.toStringAsFixed(2)}').join('、')}',
      excludeSemantics: true,
      child: Column(
        children: [
          SizedBox(
            height: 120,
            width: double.infinity,
            child: CustomPaint(
              painter: _TrendPainter(
                values: [for (final p in points) p.$2],
                line: colors.accent,
                dot: colors.surface,
                grid: colors.hairline,
                labelStyle: labelStyle ?? const TextStyle(fontSize: 11),
              ),
            ),
          ),
          const SizedBox(height: NiuSpacing.xs),
          Row(
            children: [
              for (final p in points)
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(p.$1, style: labelStyle),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter({
    required this.values,
    required this.line,
    required this.dot,
    required this.grid,
    required this.labelStyle,
  });
  final List<double> values;
  final Color line, dot, grid;
  final TextStyle labelStyle;

  @override
  void paint(Canvas canvas, Size size) {
    // Keep 4.3 on top and start half a point under the lowest term, so
    // a 3.6 → 3.9 change is visible instead of flat against a 0 baseline.
    const top = 4.3, labelSpace = 18.0;
    final bottom = (values.reduce((a, b) => a < b ? a : b) - .5)
        .floorToDouble()
        .clamp(0.0, 3.0);
    final step = size.width / values.length;
    Offset at(int i) => Offset(
      step * (i + .5),
      labelSpace +
          (size.height - labelSpace - 6) *
              (1 - (values[i].clamp(bottom, top) - bottom) / (top - bottom)),
    );
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (final y in [labelSpace, size.height - 6]) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    final path = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < values.length; i++) {
      path.lineTo(at(i).dx, at(i).dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    for (var i = 0; i < values.length; i++) {
      final p = at(i);
      canvas.drawCircle(p, 5, Paint()..color = dot);
      canvas.drawCircle(
        p,
        5,
        Paint()
          ..color = line
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      final text = TextPainter(
        text: TextSpan(text: values[i].toStringAsFixed(2), style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      text.paint(canvas, p - Offset(text.width / 2, text.height + 6));
    }
  }

  @override
  bool shouldRepaint(_TrendPainter old) =>
      old.values != values ||
      old.line != line ||
      old.dot != dot ||
      old.grid != grid ||
      old.labelStyle != labelStyle;
}

/// A course with its type and, in 歷年, its credits; failing scores in red,
/// textual ones (通過、抵免、尚未公布) muted.
class GradeCourseRow extends StatelessWidget {
  const GradeCourseRow({
    super.key,
    required this.course,
    this.showCredits = false,
    this.padding = EdgeInsets.zero,
  });
  final GradeCourse course;
  final bool showCredits;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = NiuColors.of(context);
    final numeric = double.tryParse(course.score) != null;
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(course.name, style: theme.textTheme.titleMedium),
                const SizedBox(height: NiuSpacing.xs),
                Wrap(
                  spacing: NiuSpacing.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    NiuBadge(label: course.category),
                    if (showCredits)
                      Text(
                        '${_credits(course.credits)} 學分',
                        style: theme.textTheme.bodySmall,
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: NiuSpacing.md),
          Text(
            course.score,
            style:
                (numeric
                        ? theme.textTheme.titleLarge
                        : theme.textTheme.titleSmall?.copyWith(
                            color: colors.inkSecondary,
                          ))
                    ?.copyWith(
                      color: course.failed ? colors.error : null,
                      fontFeatures: tabularFigures,
                    ),
          ),
        ],
      ),
    );
  }
}

/// One 歷年 term: rank, GPA, average and pass rate, then its courses —
/// all of them when expanded, otherwise the first and a count of the rest.
class GradeSemesterCard extends StatelessWidget {
  const GradeSemesterCard({
    super.key,
    required this.semester,
    required this.expanded,
    required this.onToggle,
  });
  final GradeSemester semester;
  final bool expanded;
  final VoidCallback onToggle;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = NiuColors.of(context);
    final stats = semester.stats;
    final courses = expanded
        ? semester.courses
        : semester.courses.take(1).toList();
    final hidden = semester.courses.length - courses.length;
    return NiuCard(
      padding: const EdgeInsets.fromLTRB(
        NiuSpacing.lg,
        NiuSpacing.sm,
        NiuSpacing.lg,
        NiuSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            expanded: expanded,
            label: '${semester.year} 學年度${semester.termTitle}',
            value: semester.rankLabel.isEmpty ? null : semester.rankLabel,
            excludeSemantics: true,
            child: InkWell(
              borderRadius: BorderRadius.circular(NiuRadius.md),
              onTap: onToggle,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            semester.termTitle,
                            style: theme.textTheme.titleMedium,
                          ),
                          if (semester.rankLabel.isNotEmpty)
                            Text(
                              semester.rankLabel,
                              style: theme.textTheme.bodySmall,
                            ),
                        ],
                      ),
                    ),
                    AnimatedRotation(
                      turns: expanded ? 0 : -0.25,
                      duration: NiuMotion.duration(context),
                      child: Icon(
                        Icons.expand_more_rounded,
                        color: colors.inkSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: NiuSpacing.sm),
          Row(
            children: [
              Expanded(
                child: NiuStat(
                  label: '學期 GPA',
                  value: stats.gpa?.toStringAsFixed(2) ?? '—',
                ),
              ),
              Expanded(
                child: NiuStat(
                  label: '平均分數',
                  value: semester.average?.toStringAsFixed(1) ?? '—',
                ),
              ),
              Expanded(
                child: NiuStat(label: '通過率', value: _percent(stats.passRate)),
              ),
            ],
          ),
          const SizedBox(height: NiuSpacing.md),
          NiuProgressBar(
            value: stats.passRate ?? 0,
            height: 6,
            semanticLabel: '通過率',
          ),
          for (final c in courses) ...[
            Divider(height: NiuSpacing.xxl, color: colors.hairline),
            GradeCourseRow(course: c, showCredits: true),
          ],
          if (hidden > 0)
            Padding(
              padding: const EdgeInsets.only(top: NiuSpacing.md),
              child: InkWell(
                borderRadius: BorderRadius.circular(NiuRadius.md),
                onTap: onToggle,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: NiuSpacing.xs),
                  child: Text(
                    '其餘 $hidden 門課程',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.accent,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
