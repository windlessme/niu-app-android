import 'package:flutter/material.dart';
import '../../shared/shared.dart';
import 'schedule_models.dart';
import 'schedule_presentation.dart';

const _lessonHues = [
  NiuHue.blue,
  NiuHue.purple,
  NiuHue.teal,
  NiuHue.orange,
  NiuHue.indigo,
  NiuHue.green,
  NiuHue.pink,
  NiuHue.cyan,
];

/// Stable per-course colour, so a course looks the same on every day.
NiuHue lessonHue(String name) {
  var hash = 0;
  for (final unit in name.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return _lessonHues[hash % _lessonHues.length];
}

int? _clock(String v) {
  final m = RegExp(r'(\d{1,2}):(\d{2})').firstMatch(v);
  return m == null ? null : int.parse(m[1]!) * 60 + int.parse(m[2]!);
}

/// Start and end minutes of a school period, when its time text has both.
(int, int)? _span(SchedulePeriod period) {
  final times = RegExp(r'\d{1,2}:\d{2}').allMatches(period.time).toList();
  if (times.length < 2) return null;
  return (_clock(times.first[0]!)!, _clock(times.last[0]!)!);
}

/// The whole week on one screen: weekdays across with their dates, periods
/// down, each course one block over its consecutive periods. Saturday and
/// Sunday appear only when they have classes; every day always fits the
/// width, so nothing scrolls sideways. Today is highlighted and a line marks
/// the current time.
class ScheduleWeekView extends StatelessWidget {
  const ScheduleWeekView({
    super.key,
    required this.schedule,
    this.now,
    this.height,
    this.onOpenCourse,
  });
  final ClassSchedule schedule;

  /// Wall-clock time in Taipei; null leaves today and the time line out.
  final DateTime? now;

  /// Height the grid may fill; rows grow to use it, within readable limits.
  final double? height;
  final void Function(String course)? onOpenCourse;

  @override
  Widget build(BuildContext context) {
    final lessons = {
      for (final day in scheduleWeekdays)
        day: scheduleLessons(schedule, day, mergeConsecutive: true),
    };
    final days = [
      for (final (i, day) in scheduleWeekdays.indexed)
        if (i < 5 || lessons[day]!.isNotEmpty) i,
    ];
    final index = {for (final (i, p) in schedule.periods.indexed) p.label: i};
    final used = [
      for (final list in lessons.values)
        for (final lesson in list)
          for (final p in lesson.periods) index[p] ?? -1,
    ].where((i) => i >= 0).toList();
    if (used.isEmpty) {
      return const NiuCard(
        child: NiuEmpty(
          padding: EdgeInsets.symmetric(vertical: NiuSpacing.xxl),
          icon: NiuIcons.sunny,
          tone: NiuTone.warning,
          title: '這週沒有課',
        ),
      );
    }
    final first = used.reduce((a, b) => a < b ? a : b);
    final last = used.reduce((a, b) => a > b ? a : b);
    final rows = last - first + 1;
    final today = now == null ? null : now!.weekday - 1;
    final monday = now == null
        ? null
        : DateTime(now!.year, now!.month, now!.day - (now!.weekday - 1));

    final scale = MediaQuery.textScalerOf(context);
    final minRow = scale.scale(58).clamp(58, 110).toDouble();
    final available = (height ?? 0) - scale.scale(52);
    final rowHeight = (available / rows).clamp(minRow, minRow * 1.6).toDouble();
    final labelWidth = scale.scale(34).clamp(34, 52).toDouble();
    final colors = NiuColors.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final column = (constraints.maxWidth - labelWidth) / days.length;
        final compact = column < 56;
        final gridHeight = rowHeight * rows;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                SizedBox(width: labelWidth),
                for (final d in days)
                  SizedBox(
                    width: column,
                    child: _DayHeader(
                      day: d,
                      date: monday?.add(Duration(days: d)),
                      today: d == today,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: NiuSpacing.sm),
            SizedBox(
              height: gridHeight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: labelWidth,
                    child: Column(
                      children: [
                        for (var p = first; p <= last; p++)
                          SizedBox(
                            height: rowHeight,
                            child: _PeriodLabel(period: schedule.periods[p]),
                          ),
                      ],
                    ),
                  ),
                  for (final d in days)
                    SizedBox(
                      width: column,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned.fill(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: d == today ? colors.accentSoft : null,
                                borderRadius: BorderRadius.circular(
                                  NiuRadius.sm,
                                ),
                              ),
                            ),
                          ),
                          for (var p = first + 1; p <= last; p++)
                            Positioned(
                              top: rowHeight * (p - first),
                              left: 0,
                              right: 0,
                              child: Divider(
                                height: 1,
                                thickness: 1,
                                color: colors.hairline,
                              ),
                            ),
                          for (final lesson in lessons[scheduleWeekdays[d]]!)
                            if (index[lesson.periods.first] case final start?)
                              Positioned(
                                top: rowHeight * (start - first) + 2,
                                left: 2,
                                right: 2,
                                height: rowHeight * lesson.periods.length - 4,
                                child: _LessonBlock(
                                  lesson: lesson,
                                  compact: compact,
                                  current:
                                      d == today &&
                                      _within(
                                        lesson,
                                        now!.hour * 60 + now!.minute,
                                      ),
                                  onTap: () => _showLesson(context, lesson),
                                ),
                              ),
                          if (d == today)
                            if (_nowOffset(first, last, rowHeight)
                                case final y?)
                              Positioned(
                                top: y - 5,
                                left: -5,
                                right: 0,
                                child: const _NowLine(),
                              ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  /// Where the current time falls in the grid, or null outside the shown
  /// periods. Between two periods the line rests on the boundary.
  double? _nowOffset(int first, int last, double rowHeight) {
    if (now == null) return null;
    final minute = now!.hour * 60 + now!.minute;
    for (var p = first; p <= last; p++) {
      final span = _span(schedule.periods[p]);
      if (span == null) continue;
      final (start, end) = span;
      final top = rowHeight * (p - first);
      if (minute < start) return p == first ? null : top;
      if (minute < end) {
        return top + rowHeight * (minute - start) / (end - start);
      }
    }
    return null;
  }

  static bool _within(ScheduleLesson lesson, int minute) {
    final start = _clock(lesson.start), end = _clock(lesson.end);
    return start != null && end != null && start <= minute && minute < end;
  }

  void _showLesson(BuildContext context, ScheduleLesson lesson) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheet) {
        final text = Theme.of(sheet).textTheme;
        final hue = lessonHue(lesson.name);
        return SafeArea(
          top: false,
          child: Padding(
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
                Row(
                  children: [
                    Container(
                      width: 4,
                      height: 28,
                      decoration: BoxDecoration(
                        color: hue.foreground(sheet),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: NiuSpacing.md),
                    Expanded(child: Text(lesson.name, style: text.titleLarge)),
                  ],
                ),
                const SizedBox(height: NiuSpacing.md),
                NiuKeyValue(
                  label: '時間',
                  value:
                      '${lesson.day}・${lesson.periodLabel}・${lesson.start}–${lesson.end}',
                ),
                if (lesson.room.isNotEmpty)
                  NiuKeyValue(label: '教室', value: lesson.room),
                if (lesson.teacher.isNotEmpty)
                  NiuKeyValue(label: '老師', value: lesson.teacher),
                if (onOpenCourse != null) ...[
                  const SizedBox(height: NiuSpacing.lg),
                  FilledButton.tonalIcon(
                    onPressed: () {
                      Navigator.pop(sheet);
                      onOpenCourse!(lesson.name);
                    },
                    icon: const Icon(NiuIcons.forward),
                    label: const Text('開啟 M 園區課程'),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.day, this.date, required this.today});
  final int day;
  final DateTime? date;
  final bool today;
  @override
  Widget build(BuildContext context) {
    final colors = NiuColors.of(context);
    final text = Theme.of(context).textTheme;
    final fg = today ? colors.onAccent : colors.ink;
    return Semantics(
      label: [
        if (today) '今天',
        scheduleWeekdays[day],
        if (date != null) '${date!.month} 月 ${date!.day} 日',
      ].join('，'),
      excludeSemantics: true,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: today ? colors.accent : null,
            borderRadius: BorderRadius.circular(NiuRadius.md),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                scheduleWeekdays[day].substring(2),
                style: text.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: fg,
                ),
              ),
              if (date != null)
                Text(
                  '${date!.month}/${date!.day}',
                  maxLines: 1,
                  style: text.labelSmall?.copyWith(
                    fontFeatures: tabularFigures,
                    color: today ? colors.onAccent : colors.inkTertiary,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PeriodLabel extends StatelessWidget {
  const _PeriodLabel({required this.period});
  final SchedulePeriod period;
  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = NiuColors.of(context);
    final span = _span(period);
    String clock(int m) => '${m ~/ 60}:${(m % 60).toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.only(top: 4, right: 4),
      child: Column(
        children: [
          Text(
            schedulePeriodNumber(period.label),
            style: text.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.inkSecondary,
            ),
          ),
          if (span != null)
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                clock(span.$1),
                style: text.labelSmall?.copyWith(
                  fontFeatures: tabularFigures,
                  color: colors.inkTertiary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Red line with a dot at the left edge, as calendar apps mark "now".
class _NowLine extends StatelessWidget {
  const _NowLine();
  @override
  Widget build(BuildContext context) {
    final color = NiuColors.of(context).error;
    return Semantics(
      label: '現在時間',
      child: SizedBox(
        height: 10,
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            Expanded(child: Container(height: 2, color: color)),
          ],
        ),
      ),
    );
  }
}

class _LessonBlock extends StatelessWidget {
  const _LessonBlock({
    required this.lesson,
    required this.compact,
    required this.current,
    required this.onTap,
  });
  final ScheduleLesson lesson;
  final bool compact, current;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final hue = lessonHue(lesson.name);
    final text = Theme.of(context).textTheme;
    final colors = NiuColors.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final accent = hue.foreground(context);
    return Semantics(
      button: true,
      label: [
        lesson.name,
        lesson.day,
        lesson.periodLabel,
        '${lesson.start} 到 ${lesson.end}',
        if (lesson.room.isNotEmpty) lesson.room,
        if (current) '上課中',
      ].join('，'),
      excludeSemantics: true,
      child: Material(
        color: Color.alphaBlend(
          accent.withValues(alpha: dark ? .30 : .16),
          colors.surface,
        ),
        borderRadius: BorderRadius.circular(NiuRadius.sm),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: accent, width: 3)),
            ),
            padding: EdgeInsets.fromLTRB(compact ? 4 : 6, 4, 3, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Flexible(
                  child: Text(
                    lesson.name,
                    maxLines: lesson.periods.length * 2 + 1,
                    overflow: TextOverflow.ellipsis,
                    style: (compact ? text.labelSmall : text.labelMedium)
                        ?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: colors.ink,
                          height: 1.2,
                        ),
                  ),
                ),
                if (lesson.room.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    lesson.room,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: text.labelSmall?.copyWith(
                      color: colors.inkSecondary,
                      height: 1.15,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
