import 'package:flutter/material.dart';

import '../../shared/shared.dart';
import '../schedule/schedule_presentation.dart';
import 'schedule_exchange_screen.dart' show ClassmateAvatar;
import 'schedule_share.dart';

/// 「週二・第 3–4 節・10:10–12:00」 for rows [from]–[to] of [base].
String periodRunLabel(ScheduleSharePayload base, int day, int from, int to) {
  String clock(int m) => '${m ~/ 60}:${(m % 60).toString().padLeft(2, '0')}';
  final a = schedulePeriodNumber(base.periods[from].id);
  final b = schedulePeriodNumber(base.periods[to].id);
  return '週${'一二三四五六日'[day]}・第 ${a == b ? a : '$a–$b'} 節・'
      '${clock(base.periods[from].start)}–${clock(base.periods[to].end)}';
}

/// Who is free when, on [base]'s rows. [people] starts with the student.
class GroupAvailability {
  GroupAvailability(this.base, this.people, this.names)
    : assert(people.length == names.length);
  final ScheduleSharePayload base;
  final List<ScheduleSharePayload> people;
  final List<String> names;

  int get size => people.length;

  /// Rows between the first and last period anyone has class: free
  /// evenings after everyone's last class are not worth a row.
  late final List<int> rows = () {
    final busy = [
      for (final (row, p) in base.periods.indexed)
        if (base.days.any(
          (day) => people.any((e) => e.busy(day, p.start, p.end)),
        ))
          row,
    ];
    if (busy.isEmpty) return const <int>[];
    return [for (var row = busy.first; row <= busy.last; row++) row];
  }();

  /// Indexes into [people] free at `day * 100 + row`: no class then, and a
  /// table that covers the time. Times a table leaves out are not free.
  late final Map<int, List<int>> free = {
    for (final row in rows)
      for (final day in base.days)
        day * 100 + row: [
          for (final (i, p) in people.indexed)
            if (isFree(p, day, row)) i,
        ],
  };

  bool isFree(ScheduleSharePayload p, int day, int row) {
    final period = base.periods[row];
    return !p.busy(day, period.start, period.end) &&
        p.covers(day, period.start, period.end);
  }

  int countAt(int key) => free[key]?.length ?? 0;

  /// Where everyone is free.
  Set<int> get common => {
    for (final e in free.entries)
      if (e.value.length == size) e.key,
  };

  /// Where the most people, though not everyone, are free; empty when that
  /// is fewer than two.
  Set<int> get mostFree {
    final counts = [
      for (final v in free.values)
        if (v.length < size) v.length,
    ];
    if (counts.isEmpty) return const {};
    final best = counts.reduce((a, b) => a > b ? a : b);
    if (best < 2) return const {};
    return {
      for (final e in free.entries)
        if (e.value.length == best) e.key,
    };
  }

  /// [keys] joined into runs of consecutive rows on the same day with the
  /// same people free.
  List<({String line, List<int> free})> runs(Set<int> keys) {
    final result = <({String line, List<int> free})>[];
    for (final day in base.days) {
      final dayRows = [
        for (final row in rows)
          if (keys.contains(day * 100 + row)) row,
      ];
      for (var i = 0; i < dayRows.length;) {
        final who = free[day * 100 + dayRows[i]]!;
        var j = i;
        while (j + 1 < dayRows.length &&
            dayRows[j + 1] == dayRows[j] + 1 &&
            _same(free[day * 100 + dayRows[j + 1]]!, who)) {
          j++;
        }
        result.add((
          line: periodRunLabel(base, day, dayRows[i], dayRows[j]),
          free: who,
        ));
        i = j + 1;
      }
    }
    return result;
  }

  static bool _same(List<int> a, List<int> b) =>
      a.length == b.length && a.indexed.every((e) => b[e.$1] == e.$2);

  /// Why person [i] is not free at [key]: the course, or a time their
  /// table does not cover.
  String busyReason(int i, int key) {
    final period = base.periods[key % 100];
    final course = people[i].courseAt(key ~/ 100, period.start, period.end);
    if (course != null) return course;
    return '課表沒有這個時段';
  }
}

/// A grid of how many in the group are free each period. Tapping a period
/// lists who is free and what the others have; tapping a name shows only
/// that person's free periods.
class GroupAvailabilityView extends StatefulWidget {
  const GroupAvailabilityView({super.key, required this.group});
  final GroupAvailability group;
  @override
  State<GroupAvailabilityView> createState() => _GroupAvailabilityViewState();
}

class _GroupAvailabilityViewState extends State<GroupAvailabilityView> {
  int? selected;
  int? focused;

  @override
  void didUpdateWidget(GroupAvailabilityView old) {
    super.didUpdateWidget(old);
    if (old.group.names.join('\n') != widget.group.names.join('\n')) {
      selected = null;
      focused = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final group = widget.group;
    final focus = focused;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (focus != null) ...[
          _FocusBar(
            name: group.names[focus],
            me: focus == 0,
            periods: group.free.values.where((v) => v.contains(focus)).length,
            onClear: () => setState(() => focused = null),
          ),
          const SizedBox(height: NiuSpacing.md),
        ],
        _HeatGrid(
          group: group,
          selected: selected,
          focused: focus,
          onSelect: (key) =>
              setState(() => selected = selected == key ? null : key),
        ),
        if (selected case final key?) ...[
          const SizedBox(height: NiuSpacing.md),
          _SlotDetail(
            group: group,
            slot: key,
            focused: focus,
            onFocus: (i) => setState(() => focused = focused == i ? null : i),
            onClose: () => setState(() => selected = null),
          ),
        ],
        _BestTimes(group: group),
      ],
    );
  }
}

class _HeatGrid extends StatelessWidget {
  const _HeatGrid({
    required this.group,
    required this.selected,
    required this.focused,
    required this.onSelect,
  });
  final GroupAvailability group;
  final int? selected, focused;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context);
    final labelWidth = scale.scale(40).clamp(40, 60).toDouble();
    final cellHeight = scale.scale(52).clamp(52, 84).toDouble();
    final text = Theme.of(context).textTheme;
    final colors = NiuColors.of(context);
    String clock(int m) => '${m ~/ 60}:${(m % 60).toString().padLeft(2, '0')}';
    return NiuCard(
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(width: labelWidth),
              for (final day in group.base.days)
                Expanded(
                  child: Center(
                    child: Text(
                      '一二三四五六日'[day],
                      style: text.labelLarge?.copyWith(color: colors.ink),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: NiuSpacing.xs),
          for (final row in group.rows)
            SizedBox(
              height: cellHeight,
              child: Row(
                children: [
                  SizedBox(
                    width: labelWidth,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            schedulePeriodNumber(group.base.periods[row].id),
                            style: text.labelLarge,
                          ),
                          Text(
                            clock(group.base.periods[row].start),
                            style: text.labelSmall?.copyWith(
                              color: colors.inkTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  for (final day in group.base.days)
                    Expanded(
                      child: _HeatCell(
                        group: group,
                        slot: day * 100 + row,
                        selected: selected == day * 100 + row,
                        focused: focused,
                        onTap: () => onSelect(day * 100 + row),
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: NiuSpacing.sm),
          _Legend(focused: focused != null),
        ],
      ),
    );
  }
}

class _HeatCell extends StatelessWidget {
  const _HeatCell({
    required this.group,
    required this.slot,
    required this.selected,
    required this.focused,
    required this.onTap,
  });
  final GroupAvailability group;
  final int slot;
  final bool selected;
  final int? focused;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = NiuColors.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final green = NiuHue.green.foreground(context);
    final blue = NiuHue.blue.foreground(context);
    final who = group.free[slot] ?? const <int>[];
    final count = who.length;
    final everyone = count == group.size;
    final focus = focused;

    Color? fill;
    Widget? mark;
    if (focus != null) {
      if (who.contains(focus)) {
        fill = blue.withValues(alpha: dark ? .45 : .28);
        mark = Icon(Icons.check_rounded, size: 18, color: blue);
      }
    } else if (everyone) {
      fill = green;
      mark = Icon(
        Icons.check_rounded,
        size: 18,
        color: dark ? colors.canvas : Colors.white,
      );
    } else if (count > 0) {
      fill = green.withValues(
        alpha: (dark ? .14 : .08) + .5 * count / group.size,
      );
      mark = Text(
        '$count',
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: green,
          fontWeight: FontWeight.w700,
        ),
      );
    }

    final day = '一二三四五六日'[slot ~/ 100];
    final period = schedulePeriodNumber(group.base.periods[slot % 100].id);
    return Padding(
      padding: const EdgeInsets.all(2),
      child: Semantics(
        button: true,
        selected: selected,
        label: '週$day第 $period 節，${group.size} 人中 $count 人有空',
        excludeSemantics: true,
        child: Material(
          color: fill ?? Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(NiuRadius.sm),
            side: BorderSide(
              color: selected ? colors.accent : colors.hairline,
              width: selected ? 2 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Center(child: mark),
          ),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.focused});
  final bool focused;
  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme.bodySmall;
    if (focused) return Text('藍色是這個人有空的時間', style: text);
    final green = NiuHue.green.foreground(context);
    Widget swatch(double alpha) => Container(
      width: 14,
      height: 14,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: green.withValues(alpha: alpha),
        borderRadius: BorderRadius.circular(3),
      ),
    );
    return ExcludeSemantics(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('少', style: text),
          const SizedBox(width: 4),
          swatch(.2),
          swatch(.4),
          swatch(.6),
          swatch(1),
          const SizedBox(width: 4),
          Text('多人有空，打勾是全員', style: text),
        ],
      ),
    );
  }
}

class _FocusBar extends StatelessWidget {
  const _FocusBar({
    required this.name,
    required this.me,
    required this.periods,
    required this.onClear,
  });
  final String name;
  final bool me;
  final int periods;
  final VoidCallback onClear;
  @override
  Widget build(BuildContext context) => NiuCard(
    child: Row(
      children: [
        ClassmateAvatar(name, me: me, size: 32),
        const SizedBox(width: NiuSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('正在看：$name', style: Theme.of(context).textTheme.titleSmall),
              Text(
                '$periods 節有空',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        TextButton(onPressed: onClear, child: const Text('看全部')),
      ],
    ),
  );
}

class _SlotDetail extends StatelessWidget {
  const _SlotDetail({
    required this.group,
    required this.slot,
    required this.focused,
    required this.onFocus,
    required this.onClose,
  });
  final GroupAvailability group;
  final int slot;
  final int? focused;
  final ValueChanged<int> onFocus;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = NiuColors.of(context);
    final who = group.free[slot] ?? const <int>[];
    final busy = [
      for (var i = 0; i < group.size; i++)
        if (!who.contains(i)) i,
    ];
    final row = slot % 100;
    return NiuCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      periodRunLabel(group.base, slot ~/ 100, row, row),
                      style: theme.textTheme.titleSmall,
                    ),
                    Text(
                      '${group.size} 人中 ${who.length} 人有空',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: who.isEmpty
                            ? colors.inkSecondary
                            : NiuHue.green.foreground(context),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '關閉',
                visualDensity: VisualDensity.compact,
                onPressed: onClose,
                icon: const Icon(Icons.close_rounded, size: 20),
              ),
            ],
          ),
          const SizedBox(height: NiuSpacing.sm),
          if (who.isEmpty)
            Text('沒有人有空', style: theme.textTheme.bodySmall)
          else
            Wrap(
              spacing: NiuSpacing.sm,
              runSpacing: NiuSpacing.xs,
              children: [
                for (final i in who)
                  FilterChip(
                    avatar: ClassmateAvatar(
                      group.names[i],
                      me: i == 0,
                      size: 24,
                    ),
                    label: Text(group.names[i]),
                    selected: focused == i,
                    showCheckmark: false,
                    tooltip: '只看${group.names[i]}有空的時間',
                    onSelected: (_) => onFocus(i),
                  ),
              ],
            ),
          if (busy.isNotEmpty) ...[
            const SizedBox(height: NiuSpacing.sm),
            for (final i in busy)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Icon(
                      Icons.event_busy_rounded,
                      size: 16,
                      color: colors.inkTertiary,
                    ),
                    const SizedBox(width: NiuSpacing.sm),
                    Expanded(
                      child: Text(
                        '${group.names[i]}・${group.busyReason(i, slot)}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _BestTimes extends StatelessWidget {
  const _BestTimes({required this.group});
  final GroupAvailability group;
  @override
  Widget build(BuildContext context) {
    final common = group.common;
    if (common.isNotEmpty) {
      return NiuSection(
        title: '都沒課的時間',
        child: NiuGroup(
          insetDividers: NiuSpacing.lg,
          children: [
            for (final run in group.runs(common))
              NiuRow(
                leading: Icon(
                  Icons.check_circle_rounded,
                  color: NiuHue.green.foreground(context),
                ),
                title: run.line,
              ),
          ],
        ),
      );
    }
    final best = group.mostFree;
    if (best.isEmpty) {
      return const NiuSection(
        title: '都沒課的時間',
        child: NiuCard(
          child: NiuEmpty(
            icon: Icons.event_busy_rounded,
            title: '這學期沒有共同空堂',
            message: '試著少選幾位同學。',
          ),
        ),
      );
    }
    final runs = group.runs(best);
    return NiuSection(
      title: '最多人有空的時間',
      child: NiuGroup(
        insetDividers: NiuSpacing.lg,
        children: [
          for (final run in runs.take(8))
            NiuRow(
              leading: Text(
                '${run.free.length}/${group.size}',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: NiuHue.green.foreground(context),
                  fontWeight: FontWeight.w700,
                ),
              ),
              title: run.line,
              subtitle:
                  '沒空：${[for (var i = 0; i < group.size; i++)
                    if (!run.free.contains(i)) group.names[i]].join('、')}',
            ),
        ],
      ),
    );
  }
}
