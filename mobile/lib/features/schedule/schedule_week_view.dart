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

/// The whole week as a grid: weekdays across, periods down, each course one
/// block over its consecutive periods. Weekends appear only when used, and
/// only the periods from the first to the last class of the week are shown.
class ScheduleWeekView extends StatelessWidget {
  const ScheduleWeekView({
    super.key,
    required this.schedule,
    this.today,
    this.minute,
    this.onOpenCourse,
  });
  final ClassSchedule schedule;

  /// Index into [scheduleWeekdays] and minutes since midnight in Taipei,
  /// to mark today and the class in progress.
  final int? today, minute;
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
    final scale = MediaQuery.textScalerOf(context);
    final rowHeight = scale.scale(64).clamp(64, 120).toDouble();
    final labelWidth = scale.scale(40).clamp(40, 64).toDouble();
    final text = Theme.of(context).textTheme;
    final colors = NiuColors.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final minColumn = scale.scale(58).toDouble();
        final fit = (constraints.maxWidth - labelWidth) / days.length;
        final column = fit < minColumn ? minColumn : fit;
        final grid = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(width: labelWidth),
                for (final d in days)
                  SizedBox(
                    width: column,
                    child: Center(
                      child: _DayHeader(day: d, today: today),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: NiuSpacing.sm),
            Row(
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
                    height: rowHeight * (last - first + 1),
                    child: Stack(
                      children: [
                        // Hairlines between periods keep the rows readable.
                        for (var p = first; p <= last; p++)
                          Positioned(
                            top: rowHeight * (p - first),
                            left: 0,
                            right: 0,
                            height: rowHeight,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: d == today
                                    ? colors.accentSoft.withValues(alpha: .35)
                                    : null,
                                border: Border(
                                  top: BorderSide(color: colors.hairline),
                                ),
                              ),
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
                                current:
                                    d == today &&
                                    minute != null &&
                                    _within(lesson, minute!),
                                onTap: () => _showLesson(context, lesson),
                              ),
                            ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        );
        final width = labelWidth + column * days.length;
        return DefaultTextStyle.merge(
          style: text.bodySmall,
          child: width <= constraints.maxWidth + 0.5
              ? grid
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(width: width, child: grid),
                ),
        );
      },
    );
  }

  static bool _within(ScheduleLesson lesson, int minute) {
    int? clock(String v) {
      final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(v);
      return m == null ? null : int.parse(m[1]!) * 60 + int.parse(m[2]!);
    }

    final start = clock(lesson.start), end = clock(lesson.end);
    return start != null && end != null && start <= minute && minute < end;
  }

  void _showLesson(BuildContext context, ScheduleLesson lesson) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheet) {
        final text = Theme.of(sheet).textTheme;
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
                Text(lesson.name, style: text.titleLarge),
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
  const _DayHeader({required this.day, required this.today});
  final int day;
  final int? today;
  @override
  Widget build(BuildContext context) {
    final colors = NiuColors.of(context);
    final isToday = day == today;
    final label = scheduleWeekdays[day].substring(2);
    return Semantics(
      label: isToday ? '今天，${scheduleWeekdays[day]}' : scheduleWeekdays[day],
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isToday ? colors.accent : null,
          borderRadius: BorderRadius.circular(NiuRadius.pill),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: isToday ? colors.onAccent : colors.inkSecondary,
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
    final start = RegExp(r'\d{1,2}:\d{2}').firstMatch(period.time)?.group(0);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        children: [
          Text(
            schedulePeriodNumber(period.label),
            style: text.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.inkSecondary,
            ),
          ),
          if (start != null)
            Text(
              start,
              style: text.labelSmall?.copyWith(
                fontFeatures: tabularFigures,
                color: colors.inkTertiary,
              ),
            ),
        ],
      ),
    );
  }
}

class _LessonBlock extends StatelessWidget {
  const _LessonBlock({
    required this.lesson,
    required this.current,
    required this.onTap,
  });
  final ScheduleLesson lesson;
  final bool current;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final hue = lessonHue(lesson.name);
    final text = Theme.of(context).textTheme;
    final colors = NiuColors.of(context);
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
        color: hue.background(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(NiuRadius.sm),
          side: current
              ? BorderSide(color: colors.accent, width: 2)
              : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 5, 4, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Flexible(
                  child: Text(
                    lesson.name,
                    overflow: TextOverflow.fade,
                    style: text.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: hue.foreground(context),
                      height: 1.2,
                    ),
                  ),
                ),
                if (lesson.room.isNotEmpty)
                  Text(
                    lesson.room,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.labelSmall?.copyWith(
                      color: colors.inkSecondary,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
