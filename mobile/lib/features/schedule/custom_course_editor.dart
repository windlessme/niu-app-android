import 'package:flutter/material.dart';

import '../../core/analytics/app_analytics.dart';
import '../../shared/shared.dart';
import 'course_colors.dart';
import 'custom_courses.dart';
import 'schedule_models.dart';
import 'schedule_presentation.dart';

/// Taipei calendar day for [now].
DateTime taipeiToday([DateTime? now]) {
  final t = (now ?? DateTime.now()).toUtc().add(const Duration(hours: 8));
  return DateTime(t.year, t.month, t.day);
}

/// NIU semesters end in January and June; a starting point to change.
DateTime defaultCustomCourseLastDay(DateTime today) => today.month >= 8
    ? DateTime(today.year + 1, 1, 31)
    : today.month == 1
    ? DateTime(today.year, 1, 31)
    : DateTime(today.year, 6, 30);

/// Adds or edits one custom course. Nothing here reaches the school.
class CustomCourseEditorScreen extends StatefulWidget {
  const CustomCourseEditorScreen({
    super.key,
    required this.schedule,
    required this.account,
    this.course,
    this.weekday,
    this.store,
    this.now,
  });

  /// The school timetable: its periods, and the slots already taken.
  final ClassSchedule schedule;
  final String account;
  final CustomCourse? course;

  /// Monday-based weekday to start with, for a new course.
  final int? weekday;
  final CustomCourseStore? store;
  final DateTime? now;
  @override
  State<CustomCourseEditorScreen> createState() =>
      _CustomCourseEditorScreenState();
}

class _CustomCourseEditorScreenState extends State<CustomCourseEditorScreen> {
  late final store = widget.store ?? CustomCourseStore.instance;
  late final today = taipeiToday(widget.now);
  late final original = widget.course;
  late final id = original?.id ?? CustomCourse.newId();
  late final name = TextEditingController(text: original?.name);
  late final classroom = TextEditingController(text: original?.classroom);
  late final note = TextEditingController(text: original?.note);
  late final Set<int> weekdays = {
    ...?original?.weekdays,
    if (original == null && widget.weekday != null) widget.weekday!,
  };
  late int startRow, endRow;
  late DateTime lastDay =
      (original == null ? null : CustomCourse.date(original!.lastDay)) ??
      defaultCustomCourseLastDay(today);

  /// An unknown stored value (from a newer version) shows as unselected
  /// but is kept until changed.
  late String? colorId = original?.colorId;
  bool saving = false;

  List<SchedulePeriod> get periods => widget.schedule.periods;

  @override
  void initState() {
    super.initState();
    final range = original?.rows(periods);
    // New courses start at the first morning period, not an early 「0」.
    final morning = periods.indexWhere((p) {
      final m = RegExp(r'(\d{1,2}):(\d{2})').firstMatch(p.time);
      return m != null && int.parse(m[1]!) >= 8;
    });
    final first = morning < 0 ? 0 : morning;
    startRow = range?.$1 ?? first;
    endRow = range?.$2 ?? first;
  }

  @override
  void dispose() {
    name.dispose();
    classroom.dispose();
    note.dispose();
    super.dispose();
  }

  CustomCourse? get draft => periods.isEmpty
      ? null
      : CustomCourse(
          id: id,
          name: name.text.trim(),
          classroom: classroom.text.trim(),
          note: note.text.trim(),
          weekdays: weekdays.toList()..sort(),
          startPeriod: periods[startRow].label,
          endPeriod: periods[endRow < startRow ? startRow : endRow].label,
          lastDay: CustomCourse.day(lastDay),
          colorId: colorId,
        );

  String? get conflict {
    final course = draft;
    if (course == null || weekdays.isEmpty) return null;
    return widget.schedule.conflict(
      course,
      store.coursesFor(widget.account),
      today,
    );
  }

  bool get canSave =>
      !saving &&
      name.text.trim().isNotEmpty &&
      weekdays.isNotEmpty &&
      draft != null &&
      conflict == null;

  Future<void> save() async {
    final course = draft;
    if (!canSave || course == null) return;
    setState(() => saving = true);
    try {
      await store.save(widget.account, course);
      AppAnalytics.instance.event('custom_course', {
        'action': original == null ? 'add' : 'edit',
        'color': colorId == null
            ? 'auto'
            : colourFromHex(colorId!) != null
            ? 'picked'
            : 'preset',
      });
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() => saving = false);
        showNiuMessage(context, '沒有儲存，請再試一次');
      }
    }
  }

  Future<void> delete() async {
    final ok =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('要刪除「${original!.name}」嗎？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: NiuColors.of(context).error,
                ),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('刪除課程'),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok || !mounted) return;
    await store.delete(widget.account, id);
    AppAnalytics.instance.event('custom_course', {'action': 'delete'});
    if (mounted) Navigator.pop(context, true);
  }

  String periodLabel(int row) {
    final p = periods[row];
    final times = RegExp(r'\d{1,2}:\d{2}').allMatches(p.time).toList();
    final time = times.length < 2 ? '' : '  ${times.first[0]}–${times.last[0]}';
    return '第 ${schedulePeriodNumber(p.label)} 節$time';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = NiuColors.of(context);
    final expired =
        CustomCourse.day(lastDay).compareTo(CustomCourse.day(today)) < 0;
    final problem = conflict;
    return Scaffold(
      appBar: NiuAppBar(
        title: original == null ? '新增課程' : '編輯課程',
        actions: [
          TextButton(onPressed: canSave ? save : null, child: const Text('儲存')),
        ],
      ),
      body: ListView(
        padding: NiuLayout.page(
          context,
          top: NiuSpacing.md,
          bottom: NiuSpacing.huge,
        ),
        children: [
          NiuCard(
            child: Column(
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: '課程名稱'),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: NiuSpacing.md),
                TextField(
                  controller: classroom,
                  decoration: const InputDecoration(labelText: '地點（選填）'),
                ),
                const SizedBox(height: NiuSpacing.md),
                TextField(
                  controller: note,
                  decoration: const InputDecoration(labelText: '教師或備註（選填）'),
                ),
              ],
            ),
          ),
          NiuSection(
            title: '上課時間',
            child: NiuCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('星期', style: theme.textTheme.labelMedium),
                  const SizedBox(height: NiuSpacing.sm),
                  Row(
                    children: [
                      for (var d = 0; d < 7; d++)
                        Expanded(
                          child: Semantics(
                            label: scheduleWeekdays[d],
                            selected: weekdays.contains(d),
                            button: true,
                            excludeSemantics: true,
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: () => setState(
                                () => weekdays.contains(d)
                                    ? weekdays.remove(d)
                                    : weekdays.add(d),
                              ),
                              child: Container(
                                height: 40,
                                alignment: Alignment.center,
                                margin: const EdgeInsets.all(2),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: weekdays.contains(d)
                                      ? colors.accent
                                      : colors.fill,
                                ),
                                child: Text(
                                  CustomCourse.shortWeekdays[d],
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    color: weekdays.contains(d)
                                        ? colors.onAccent
                                        : colors.ink,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: NiuSpacing.lg),
                  if (periods.isEmpty)
                    Text('課表沒有節次資料，請先更新課表', style: theme.textTheme.bodySmall)
                  else ...[
                    DropdownButtonFormField<int>(
                      initialValue: startRow,
                      decoration: const InputDecoration(labelText: '開始節次'),
                      items: [
                        for (var i = 0; i < periods.length; i++)
                          DropdownMenuItem(
                            value: i,
                            child: Text(periodLabel(i)),
                          ),
                      ],
                      onChanged: (v) => setState(() {
                        startRow = v!;
                        if (endRow < startRow) endRow = startRow;
                      }),
                    ),
                    const SizedBox(height: NiuSpacing.md),
                    DropdownButtonFormField<int>(
                      key: ValueKey(startRow),
                      initialValue: endRow < startRow ? startRow : endRow,
                      decoration: const InputDecoration(labelText: '結束節次'),
                      items: [
                        for (var i = startRow; i < periods.length; i++)
                          DropdownMenuItem(
                            value: i,
                            child: Text(periodLabel(i)),
                          ),
                      ],
                      onChanged: (v) => setState(() => endRow = v!),
                    ),
                  ],
                  const SizedBox(height: NiuSpacing.md),
                  if (problem != null)
                    NiuBanner(
                      tone: NiuTone.warning,
                      message: '$problem，請改選其他時段',
                    )
                  else if (weekdays.isEmpty)
                    Text('請至少選擇一天', style: theme.textTheme.bodySmall)
                  else if (draft case final course?)
                    Text(
                      course.summary(periods),
                      style: theme.textTheme.bodySmall,
                    ),
                ],
              ),
            ),
          ),
          NiuSection(
            title: '顏色',
            subtitle: '「自動」會依課程名稱配色；最後一格可以自選顏色。',
            child: NiuCard(
              child: CourseColorPicker(
                value: colorId,
                onChanged: (v) => setState(() => colorId = v),
              ),
            ),
          ),
          NiuSection(
            title: '期限',
            subtitle: expired
                ? '這個日期已經過了，課程不會顯示在課表上'
                : '到期日當天仍會顯示，之後就不會再出現在課表上。',
            child: NiuGroup(
              children: [
                NiuRow(
                  icon: NiuIcons.calendar,
                  hue: NiuHue.red,
                  title: '到期日',
                  value: CustomCourse.day(lastDay).replaceAll('-', '/'),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: lastDay,
                      firstDate: DateTime(today.year - 1),
                      lastDate: DateTime(today.year + 3, 12, 31),
                      helpText: '到期日',
                    );
                    if (picked != null) setState(() => lastDay = picked);
                  },
                ),
              ],
            ),
          ),
          if (original != null) ...[
            const SizedBox(height: NiuSpacing.section),
            OutlinedButton(
              style: OutlinedButton.styleFrom(foregroundColor: colors.error),
              onPressed: delete,
              child: const Text('刪除課程'),
            ),
          ],
          const SizedBox(height: NiuSpacing.lg),
          Text('自訂課程只存在這支手機，不會傳送到學校系統。', style: theme.textTheme.labelMedium),
        ],
      ),
    );
  }
}

/// 「自動」, the presets, and a swatch that opens a picker for any colour.
class CourseColorPicker extends StatelessWidget {
  const CourseColorPicker({
    super.key,
    required this.value,
    required this.onChanged,
  });
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final picked = value == null ? null : colourFromHex(value!);
    return Wrap(
      spacing: NiuSpacing.xs,
      runSpacing: NiuSpacing.xs,
      children: [
        _Swatch(
          label: '自動',
          selected: value == null,
          icon: Icons.auto_awesome_rounded,
          onTap: () => onChanged(null),
        ),
        for (final preset in CustomCourseColor.values)
          _Swatch(
            label: preset.title,
            colour: preset.tint.foreground(context),
            selected: value == preset.name,
            onTap: () => onChanged(preset.name),
          ),
        _Swatch(
          label: '自選顏色',
          colour: picked,
          icon: picked == null ? Icons.palette_outlined : null,
          selected: picked != null,
          onTap: () async {
            final colour = await showModalBottomSheet<Color>(
              context: context,
              isScrollControlled: true,
              builder: (_) =>
                  _ColourSheet(initial: picked ?? NiuHue.blue.light),
            );
            if (colour != null) onChanged(hexFromColour(colour));
          },
        ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.label,
    required this.selected,
    required this.onTap,
    this.colour,
    this.icon,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? colour;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = NiuColors.of(context);
    final fill = colour ?? colors.fill;
    // A ring and a check mark the choice without relying on colour alone.
    final check = ThemeData.estimateBrightnessForColor(fill) == Brightness.dark
        ? Colors.white
        : Colors.black;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        child: InkResponse(
          onTap: onTap,
          radius: 24,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (selected)
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: colors.ink, width: 2),
                    ),
                  ),
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: fill,
                  ),
                  child: icon != null
                      ? Icon(icon, size: 18, color: colors.inkSecondary)
                      : selected
                      ? Icon(Icons.check_rounded, size: 18, color: check)
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Hue, saturation and brightness sliders with a preview.
class _ColourSheet extends StatefulWidget {
  const _ColourSheet({required this.initial});
  final Color initial;
  @override
  State<_ColourSheet> createState() => _ColourSheetState();
}

class _ColourSheetState extends State<_ColourSheet> {
  late HSVColor colour = HSVColor.fromColor(widget.initial);

  Widget slider(
    String label,
    double value,
    double max,
    HSVColor Function(double) set,
  ) => Row(
    children: [
      SizedBox(
        width: 56,
        child: Text(label, style: Theme.of(context).textTheme.labelLarge),
      ),
      Expanded(
        child: Slider(
          value: value,
          max: max,
          label: label,
          onChanged: (v) => setState(() => colour = set(v)),
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final result = colour.toColor();
    return SafeArea(
      child: Padding(
        padding: NiuLayout.page(context, bottom: NiuSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('自選顏色', style: text.titleLarge),
            const SizedBox(height: NiuSpacing.lg),
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: result,
                  ),
                ),
                const SizedBox(width: NiuSpacing.md),
                Text(hexFromColour(result), style: text.titleMedium),
              ],
            ),
            const SizedBox(height: NiuSpacing.md),
            slider('色相', colour.hue, 360, (v) => colour.withHue(v % 360)),
            slider('飽和度', colour.saturation, 1, colour.withSaturation),
            slider('亮度', colour.value, 1, colour.withValue),
            const SizedBox(height: NiuSpacing.md),
            FilledButton(
              onPressed: () => Navigator.pop(context, result),
              child: const Text('使用這個顏色'),
            ),
          ],
        ),
      ),
    );
  }
}
