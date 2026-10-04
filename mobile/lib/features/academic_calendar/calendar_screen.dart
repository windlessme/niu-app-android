import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'calendar_providers.dart';
import '../../core/time/campus_date.dart';
import '../../shared/shared.dart';
import 'calendar_repository.dart';

// Index each snapshot once, independently of widget rebuilds and date selection.
final _calendarIndexProvider = Provider.autoDispose
    .family<Map<String, List<CalendarEvent>>, int>((ref, year) {
      final events =
          ref.watch(calendarProvider(year)).asData?.value.events ??
          <CalendarEvent>[];
      final index = <String, List<CalendarEvent>>{};
      for (final event in events) {
        var date = DateTime.utc(
          event.start.year,
          event.start.month,
          event.start.day,
        );
        final end = DateTime.utc(
          event.end.year,
          event.end.month,
          event.end.day,
        );
        while (!date.isAfter(end)) {
          final key = CampusDate(date.year, date.month, date.day).toString();
          index.putIfAbsent(key, () => []).add(event);
          date = date.add(const Duration(days: 1));
        }
      }
      return index;
    });

class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});
  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen>
    with WidgetsBindingObserver {
  CampusDate today = CampusDate.at(DateTime.now());
  late CampusDate selected = today;
  late DateTime month = DateTime.utc(today.year, today.month);
  final search = TextEditingController();
  String query = '';
  String? category;
  bool agenda = false;
  Timer? timer;
  int get year => CampusDate(month.year, month.month, 1).academicYear;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scheduleMidnight();
  }

  void _scheduleMidnight() {
    timer?.cancel();
    final now = DateTime.now().toUtc();
    final current = CampusDate.at(now);
    final midnight = DateTime.utc(
      current.year,
      current.month,
      current.day + 1,
    ).subtract(const Duration(hours: 8));
    timer = Timer(midnight.difference(now), () {
      _dateChanged();
      _scheduleMidnight();
    });
  }

  void _dateChanged() {
    final next = CampusDate.at(DateTime.now());
    if (next.compareTo(today) == 0 || !mounted) return;
    setState(() {
      if (selected.compareTo(today) == 0) {
        selected = next;
        month = DateTime.utc(next.year, next.month);
      }
      today = next;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _dateChanged();
      _scheduleMidnight();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    timer?.cancel();
    search.dispose();
    super.dispose();
  }

  void _move(int offset) => setState(() {
    month = DateTime.utc(month.year, month.month + offset);
    selected = CampusDate(month.year, month.month, 1);
  });
  Future<void> _refresh() async {
    ref.invalidate(calendarYearsProvider);
    ref.invalidate(calendarProvider(year));
    try {
      await ref.read(calendarProvider(year).future);
    } catch (_) {
      /* Display provider error. */
    }
  }

  void _goToday() => setState(() {
    today = CampusDate.at(DateTime.now());
    selected = today;
    month = DateTime.utc(today.year, today.month);
    query = '';
    search.clear();
    category = null;
  });

  @override
  Widget build(BuildContext context) {
    final snapshot = ref.watch(calendarProvider(year));
    final years = ref.watch(calendarYearsProvider).asData?.value ?? <int>[];
    final choices = <int>{...years, year}.toList()
      ..sort((a, b) => b.compareTo(a));
    final theme = Theme.of(context);
    return NiuScrollPage(
      title: '行事曆',
      onRefresh: _refresh,
      actions: [TextButton(onPressed: _goToday, child: const Text('今天'))],
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                NiuSegmented<bool>(
                  value: agenda,
                  segments: const [(false, '月曆'), (true, '列表')],
                  onChanged: (value) => setState(() => agenda = value),
                ),
                const SizedBox(height: NiuSpacing.md),
                NiuSearchField(
                  controller: search,
                  hint: '搜尋這個學年度的行事曆',
                  onChanged: (value) => setState(() => query = value.trim()),
                ),
                const SizedBox(height: NiuSpacing.md),
                Wrap(
                  spacing: NiuSpacing.sm,
                  runSpacing: NiuSpacing.sm,
                  children: [
                    PopupMenuButton<int>(
                      tooltip: '切換學年度',
                      initialValue: year,
                      onSelected: (value) => setState(() {
                        month = DateTime.utc(value + 1911, 8);
                        selected = CampusDate(value + 1911, 8, 1);
                      }),
                      itemBuilder: (_) => choices
                          .map(
                            (y) =>
                                PopupMenuItem(value: y, child: Text('$y 學年度')),
                          )
                          .toList(),
                      child: _MenuPill(label: '$year 學年度'),
                    ),
                    PopupMenuButton<String>(
                      tooltip: '篩選類別',
                      initialValue: category ?? '',
                      onSelected: (value) => setState(
                        () => category = value.isEmpty ? null : value,
                      ),
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: '', child: Text('全部類別')),
                        ...calendarCategories.entries.map(
                          (e) => PopupMenuItem(
                            value: e.key,
                            child: Row(
                              children: [
                                _Dot(color: categoryColor(context, e.key)),
                                const SizedBox(width: NiuSpacing.md),
                                Text(e.value),
                              ],
                            ),
                          ),
                        ),
                      ],
                      child: _MenuPill(
                        label: calendarCategories[category] ?? '全部類別',
                        icon: Icons.filter_list_rounded,
                        active: category != null,
                      ),
                    ),
                  ],
                ),
                if (query.isEmpty) ...[
                  const SizedBox(height: NiuSpacing.lg),
                  NiuCard(
                    padding: const EdgeInsets.fromLTRB(
                      NiuSpacing.xs,
                      NiuSpacing.sm,
                      NiuSpacing.xs,
                      NiuSpacing.lg,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const SizedBox(width: NiuSpacing.md),
                            Expanded(
                              child: Semantics(
                                header: true,
                                child: Text(
                                  '${month.year} 年 ${month.month} 月',
                                  style: theme.textTheme.titleLarge,
                                ),
                              ),
                            ),
                            NiuIconButton(
                              tooltip: '上個月',
                              onPressed: () => _move(-1),
                              icon: Icons.chevron_left_rounded,
                            ),
                            NiuIconButton(
                              tooltip: '下個月',
                              onPressed: () => _move(1),
                              icon: Icons.chevron_right_rounded,
                            ),
                          ],
                        ),
                        if (!agenda) _grid(snapshot.asData?.value),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: NiuSpacing.xl),
                snapshot.when(
                  loading: () => const NiuLoading(message: '正在讀取行事曆'),
                  error: (_, _) => NiuEmpty(
                    title: '這個學年度還沒有資料',
                    message: '切換到已公布的學年度，或稍後再重新整理。',
                    icon: NiuIcons.calendar,
                    action: FilledButton.tonal(
                      onPressed: _refresh,
                      child: const Text('重新整理'),
                    ),
                  ),
                  data: _content,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _grid(CalendarSnapshot? data) {
    final first = month.weekday % 7;
    final count = DateTime.utc(month.year, month.month + 1, 0).day;
    final indexed = ref.watch(_calendarIndexProvider(year));
    final colors = NiuColors.of(context);
    final theme = Theme.of(context);
    final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: constraints.maxWidth.clamp(
            7 * (scale > 1.5 ? 80.0 : 48.0),
            double.infinity,
          ),
          child: Column(
            children: [
              const SizedBox(height: NiuSpacing.sm),
              Row(
                children: [
                  for (final (i, d) in [
                    '日',
                    '一',
                    '二',
                    '三',
                    '四',
                    '五',
                    '六',
                  ].indexed)
                    Expanded(
                      child: Center(
                        child: Text(
                          d,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: i == 0 || i == 6
                                ? colors.inkTertiary
                                : colors.inkSecondary,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: NiuSpacing.sm),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  mainAxisExtent: 36 + 22 * scale,
                  crossAxisSpacing: 0,
                  mainAxisSpacing: 2,
                ),
                itemCount: ((first + count) / 7).ceil() * 7,
                itemBuilder: (context, index) {
                  final day = index - first + 1;
                  if (day < 1 || day > count) return const SizedBox.shrink();
                  final date = CampusDate(month.year, month.month, day);
                  final chosen = selected.compareTo(date) == 0;
                  final isToday = today.compareTo(date) == 0;
                  final matches =
                      (indexed[date.toString()] ?? <CalendarEvent>[])
                          .where(
                            (e) => category == null || e.category == category,
                          )
                          .toList();
                  final boundary = matches
                      .where((e) => e.boundary(date))
                      .toList();
                  final boundaries = boundary.length;
                  final ongoing = matches.length - boundaries;
                  final shown = boundary.take(ongoing > 0 ? 2 : 3).toList();
                  final extra =
                      matches.length - shown.length - (ongoing > 0 ? 1 : 0);
                  final weekend = index % 7 == 0 || index % 7 == 6;
                  return Semantics(
                    selected: chosen,
                    label:
                        '$date${isToday ? '，今天' : ''}，$boundaries 個當日事項，$ongoing 個期間進行中',
                    button: true,
                    child: ExcludeSemantics(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(NiuRadius.md),
                        onTap: () => setState(() => selected = date),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 34 * scale.clamp(1, 1.4),
                              height: 34 * scale.clamp(1, 1.4),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: chosen
                                    ? colors.accent
                                    : isToday
                                    ? colors.accentSoft
                                    : null,
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                '$day',
                                maxLines: 1,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontFeatures: tabularFigures,
                                  color: chosen
                                      ? colors.onAccent
                                      : isToday
                                      ? colors.accent
                                      : weekend
                                      ? colors.inkSecondary
                                      : colors.ink,
                                  fontWeight: chosen || isToday
                                      ? FontWeight.w700
                                      : FontWeight.w400,
                                ),
                              ),
                            ),
                            const SizedBox(height: 3),
                            SizedBox(
                              height: 8,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  for (final e in shown)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 1,
                                      ),
                                      child: _Dot(
                                        color: categoryColor(
                                          context,
                                          e.category,
                                        ),
                                        size: 5,
                                      ),
                                    ),
                                  if (ongoing > 0)
                                    Container(
                                      margin: const EdgeInsets.symmetric(
                                        horizontal: 1,
                                      ),
                                      width: 5,
                                      height: 5,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: colors.inkTertiary,
                                        ),
                                      ),
                                    ),
                                  if (extra > 0)
                                    Text(
                                      '+$extra',
                                      style: TextStyle(
                                        fontSize: 8,
                                        height: 1,
                                        color: colors.inkTertiary,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: NiuSpacing.md),
              Row(
                children: [
                  const SizedBox(width: NiuSpacing.md),
                  _Dot(color: colors.inkSecondary, size: 6),
                  const SizedBox(width: 6),
                  Text('當天事項', style: theme.textTheme.labelMedium),
                  const SizedBox(width: NiuSpacing.lg),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: colors.inkSecondary),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text('期間進行中', style: theme.textTheme.labelMedium),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _content(CalendarSnapshot data) {
    final theme = Theme.of(context);
    final start = CampusDate(month.year, month.month, 1);
    final end = CampusDate(
      month.year,
      month.month,
      DateTime.utc(month.year, month.month + 1, 0).day,
    );
    final events = data.events.where((e) {
      if (category != null && category != e.category) return false;
      if (query.isNotEmpty) {
        return '${e.title} ${e.note ?? ''} ${e.sourceText}'
            .toLowerCase()
            .contains(query.toLowerCase());
      }
      return agenda
          ? e.start.compareTo(end) <= 0 && e.end.compareTo(start) >= 0
          : e.contains(selected);
    }).toList();
    final sections = <String, List<CalendarEvent>>{};
    for (final e in events) {
      final key = query.isNotEmpty
          ? '搜尋結果'
          : agenda
          ? (e.start.compareTo(start) < 0
                ? '從上個月延續'
                : '${e.start.month} 月 ${e.start.day} 日')
          : (e.boundary(selected) ? '當天' : '期間進行中');
      sections.putIfAbsent(key, () => []).add(e);
    }
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    final weekday =
        weekdays[DateTime.utc(
              selected.year,
              selected.month,
              selected.day,
            ).weekday -
            1];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (data.message != null) ...[
          NiuBanner(tone: NiuTone.neutral, message: data.message!),
          const SizedBox(height: NiuSpacing.lg),
        ],
        Padding(
          padding: const EdgeInsets.only(left: NiuSpacing.xs),
          child: Semantics(
            header: true,
            child: Text(
              query.isNotEmpty
                  ? '找到 ${events.length} 個事項'
                  : agenda
                  ? '${month.month} 月・${events.length} 個事項'
                  : '${selected.month} 月 ${selected.day} 日　星期$weekday',
              style: theme.textTheme.titleLarge,
            ),
          ),
        ),
        if (query.isEmpty && agenda)
          Padding(
            padding: const EdgeInsets.only(left: NiuSpacing.xs, top: 2),
            child: Text('跨日事項只列一次', style: theme.textTheme.bodySmall),
          ),
        const SizedBox(height: NiuSpacing.md),
        if (events.isEmpty)
          NiuCard(
            child: NiuEmpty(
              padding: const EdgeInsets.symmetric(
                vertical: NiuSpacing.xl,
                horizontal: NiuSpacing.lg,
              ),
              title: query.isNotEmpty
                  ? '找不到符合的事項'
                  : '這${agenda ? '個月' : '天'}沒有排定事項',
              message: query.isNotEmpty
                  ? '試試「選課」「期中考」等關鍵字，或換個類別。'
                  : '點其他日期，或切換月份看看。',
              icon: NiuIcons.calendar,
              action: category == null
                  ? null
                  : TextButton(
                      onPressed: () => setState(() => category = null),
                      child: const Text('顯示全部類別'),
                    ),
            ),
          ),
        for (final section in sections.entries) ...[
          if (sections.length > 1 || query.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                NiuSpacing.xs,
                NiuSpacing.sm,
                0,
                NiuSpacing.sm,
              ),
              child: Semantics(
                header: true,
                child: Text(
                  section.key,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          NiuGroup(
            insetDividers: NiuSpacing.lg + 16,
            children: [
              for (final e in section.value)
                NiuRow(
                  leading: Container(
                    width: 4,
                    height: 36,
                    decoration: BoxDecoration(
                      color: categoryColor(context, e.category),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  title: e.title,
                  subtitle:
                      '${_range(e)} · ${calendarCategories[e.category] ?? e.category}',
                  onTap: () => _details(e, data),
                ),
            ],
          ),
          const SizedBox(height: NiuSpacing.md),
        ],
      ],
    );
  }

  String _range(CalendarEvent e) => e.start.compareTo(e.end) == 0
      ? '${e.start.month}/${e.start.day}'
      : '${e.start.month}/${e.start.day} – ${e.end.month}/${e.end.day}';

  void _details(CalendarEvent event, CalendarSnapshot data) {
    final source = data.sources[event.sourceId];
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      sheetAnimationStyle: MediaQuery.disableAnimationsOf(context)
          ? AnimationStyle.noAnimation
          : null,
      builder: (context) {
        final theme = Theme.of(context);
        final color = categoryColor(context, event.category);
        return SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              NiuSpacing.xxl,
              0,
              NiuSpacing.xxl,
              NiuSpacing.xxl,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    _Dot(color: color, size: 8),
                    const SizedBox(width: NiuSpacing.sm),
                    Text(
                      calendarCategories[event.category] ?? event.category,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: NiuSpacing.sm),
                Text(event.title, style: theme.textTheme.headlineSmall),
                const SizedBox(height: NiuSpacing.md),
                Row(
                  children: [
                    Icon(
                      NiuIcons.calendar,
                      size: 18,
                      color: NiuColors.of(context).inkSecondary,
                    ),
                    const SizedBox(width: NiuSpacing.sm),
                    Expanded(
                      child: Text(
                        event.start.compareTo(event.end) == 0
                            ? '${event.start}'
                            : '${event.start} – ${event.end}',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
                if (event.note?.isNotEmpty ?? false) ...[
                  const SizedBox(height: NiuSpacing.lg),
                  Text(event.note!, style: theme.textTheme.bodyMedium),
                ],
                const SizedBox(height: NiuSpacing.xl),
                Text('校方原文', style: theme.textTheme.labelMedium),
                const SizedBox(height: NiuSpacing.sm),
                NiuWell(
                  padding: const EdgeInsets.all(NiuSpacing.lg),
                  child: SelectableText(
                    event.sourceText,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                const SizedBox(height: NiuSpacing.sm),
                Text(
                  '${data.sourceLabel} · 修訂 ${data.revision}',
                  style: theme.textTheme.labelMedium,
                ),
                const SizedBox(height: NiuSpacing.xl),
                if (source != null) ...[
                  OutlinedButton.icon(
                    onPressed: () => openPublicUrl(
                      context,
                      source.replace(fragment: 'page=${event.sourcePage ?? 1}'),
                    ),
                    icon: const Icon(NiuIcons.document, size: 18),
                    label: Text('查看校方 PDF · 第 ${event.sourcePage ?? 1} 頁'),
                  ),
                  const SizedBox(height: NiuSpacing.sm),
                ],
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('完成'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color, this.size = 10});
  final Color color;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

class _MenuPill extends StatelessWidget {
  const _MenuPill({required this.label, this.icon, this.active = false});
  final String label;
  final IconData? icon;
  final bool active;
  @override
  Widget build(BuildContext context) {
    final colors = NiuColors.of(context);
    final fg = active ? colors.accent : colors.ink;
    return Container(
      constraints: const BoxConstraints(minHeight: 40),
      padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
      decoration: BoxDecoration(
        color: active ? colors.accentSoft : colors.fill,
        borderRadius: BorderRadius.circular(NiuRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: fg),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(color: fg),
          ),
          const SizedBox(width: 2),
          Icon(Icons.arrow_drop_down_rounded, size: 20, color: fg),
        ],
      ),
    );
  }
}

/// Category identity colours are distinct from success/warning/error tones.
Color categoryColor(BuildContext context, String category) =>
    switch (category) {
      'registration' => NiuHue.blue,
      'exam' => NiuHue.red,
      'holiday' => NiuHue.green,
      'deadline' => NiuHue.pink,
      'semester' => NiuHue.purple,
      'academic' => NiuHue.indigo,
      'activity' => NiuHue.cyan,
      _ => NiuHue.orange,
    }.foreground(context);
