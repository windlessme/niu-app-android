import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/providers.dart';
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

  @override
  Widget build(BuildContext context) {
    final snapshot = ref.watch(calendarProvider(year));
    final years = ref.watch(calendarYearsProvider).asData?.value ?? <int>[];
    final choices = <int>{...years, year}.toList()
      ..sort((a, b) => b.compareTo(a));
    return Scaffold(
      appBar: IosPageHeader(
        title: '行事曆',
        actions: [
          TextButton(
            style: TextButton.styleFrom(
              minimumSize: const Size(48, 48),
              backgroundColor: NiuColors.of(context).surface,
              shape: const StadiumBorder(),
            ),
            onPressed: () => setState(() {
              today = CampusDate.at(DateTime.now());
              selected = today;
              month = DateTime.utc(today.year, today.month);
              query = '';
              search.clear();
              category = null;
            }),
            child: const Text('今天'),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(
              NiuSpacing.xl,
              NiuSpacing.md,
              NiuSpacing.xl,
              NiuSpacing.xxxl,
            ),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 700),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AppSegmentedControl<bool>(
                        value: agenda,
                        segments: const {false: Text('月曆'), true: Text('事件')},
                        onChanged: (value) => setState(() => agenda = value),
                      ),
                      const SizedBox(height: NiuSpacing.lg),
                      AppSearchField(
                        controller: search,
                        hint: '搜尋此學年度的事件',
                        onChanged: (value) =>
                            setState(() => query = value.trim()),
                      ),
                      const SizedBox(height: NiuSpacing.md),
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 12,
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
                                  (y) => PopupMenuItem(
                                    value: y,
                                    child: Text('$y 學年度'),
                                  ),
                                )
                                .toList(),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              child: Text(
                                '$year 學年度 ﹀',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          PopupMenuButton<String>(
                            tooltip: '篩選事件',
                            initialValue: category ?? '',
                            onSelected: (value) => setState(
                              () => category = value.isEmpty ? null : value,
                            ),
                            itemBuilder: (_) => [
                              const PopupMenuItem(
                                value: '',
                                child: Text('全部類別'),
                              ),
                              ...calendarCategories.entries.map(
                                (e) => PopupMenuItem(
                                  value: e.key,
                                  child: Text(e.value),
                                ),
                              ),
                            ],
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    CupertinoIcons.line_horizontal_3_decrease,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(calendarCategories[category] ?? '全部類別'),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (query.isEmpty) ...[
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${month.year} 年',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                  Text(
                                    '${month.month} 月',
                                    style: const TextStyle(
                                      fontSize: 32,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            CircleIconButton(
                              tooltip: '上個月',
                              onPressed: () => _move(-1),
                              icon: CupertinoIcons.chevron_left,
                            ),
                            CircleIconButton(
                              tooltip: '下個月',
                              onPressed: () => _move(1),
                              icon: CupertinoIcons.chevron_right,
                            ),
                          ],
                        ),
                        if (!agenda) _grid(snapshot.asData?.value),
                        const SizedBox(height: NiuSpacing.xl),
                      ],
                      snapshot.when(
                        loading: () => const AppLoadingState(),
                        error: (_, _) => NiuEmptyState(
                          title: '此學年度資料尚未取得',
                          message: '請切換已公布的學年度，或稍後重新整理。',
                          icon: CupertinoIcons.calendar,
                          action: TextButton(
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
          ),
        ),
      ),
    );
  }

  Widget _grid(CalendarSnapshot? data) {
    final first = month.weekday % 7;
    final count = DateTime.utc(month.year, month.month + 1, 0).day;
    final indexed = ref.watch(_calendarIndexProvider(year));
    final color = Theme.of(context).colorScheme.onSurface;
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
              const SizedBox(height: NiuSpacing.lg),
              Row(
                children: ['日', '一', '二', '三', '四', '五', '六']
                    .map(
                      (d) => Expanded(
                        child: Center(
                          child: Text(
                            d,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: NiuSpacing.sm),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  mainAxisExtent: 40 + 32 * scale,
                  crossAxisSpacing: 0,
                  mainAxisSpacing: 4,
                ),
                itemCount: ((first + count) / 7).ceil() * 7,
                itemBuilder: (context, index) {
                  final day = index - first + 1;
                  if (day < 1 || day > count) return const SizedBox.shrink();
                  final date = CampusDate(month.year, month.month, day);
                  final chosen = selected.compareTo(date) == 0;
                  final isToday = today.compareTo(date) == 0;
                  final matches =
                      (indexed[date.toString()] ?? <CalendarEvent>[]).where(
                        (e) => category == null || e.category == category,
                      );
                  final boundaries = matches
                      .where((e) => e.boundary(date))
                      .length;
                  final ongoing = matches.length - boundaries;
                  final ink = chosen
                      ? Theme.of(context).colorScheme.surface
                      : color;
                  return Semantics(
                    selected: chosen,
                    label:
                        '$date${isToday ? '，今天' : ''}，$boundaries 個當日事項，$ongoing 個期間進行中',
                    button: true,
                    child: ExcludeSemantics(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => setState(() => selected = date),
                        child: Container(
                          decoration: BoxDecoration(
                            color: chosen ? color : null,
                            borderRadius: BorderRadius.circular(12),
                            border: isToday && !chosen
                                ? Border.all(color: color.withValues(alpha: .4))
                                : null,
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                '$day',
                                maxLines: 1,
                                style: TextStyle(
                                  color: ink,
                                  fontWeight: chosen || isToday
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                              const SizedBox(height: NiuSpacing.xs),
                              SizedBox(
                                height: 18,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    for (
                                      int i = 0;
                                      i <
                                          boundaries.clamp(
                                            0,
                                            ongoing > 0 ? 2 : 3,
                                          );
                                      i++
                                    )
                                      Container(
                                        margin: const EdgeInsets.symmetric(
                                          horizontal: 1,
                                        ),
                                        width: 4,
                                        height: 4,
                                        decoration: BoxDecoration(
                                          color: ink,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    if (ongoing > 0)
                                      Container(
                                        width: 5,
                                        height: 5,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          border: Border.all(color: ink),
                                        ),
                                      ),
                                    if (matches.length >
                                        boundaries.clamp(
                                              0,
                                              ongoing > 0 ? 2 : 3,
                                            ) +
                                            (ongoing > 0 ? 1 : 0))
                                      Text(
                                        '+${matches.length - boundaries.clamp(0, ongoing > 0 ? 2 : 3) - (ongoing > 0 ? 1 : 0)}',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: ink,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 10),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('● 當日事項　○ 期間進行中', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _content(CalendarSnapshot data) {
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
                ? '跨月期間'
                : '${e.start.month}月${e.start.day}日')
          : (e.boundary(selected)
                ? '${selected.month}月${selected.day}日・當日事項'
                : '期間進行中');
      sections.putIfAbsent(key, () => []).add(e);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (data.message != null) ...[
          NiuCard(child: Text(data.message!)),
          const SizedBox(height: NiuSpacing.lg),
        ],
        const Divider(),
        const SizedBox(height: NiuSpacing.md),
        Text(
          query.isNotEmpty
              ? '$year 學年度 · ${events.length} 個符合的事件'
              : agenda
              ? '本月共 ${events.length} 個事件 · 跨日事件僅列一次'
              : '${selected.month}月${selected.day}日 星期${['一', '二', '三', '四', '五', '六', '日'][DateTime.utc(selected.year, selected.month, selected.day).weekday - 1]}',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        if (query.isEmpty && !agenda) ...[
          const SizedBox(height: NiuSpacing.sm),
          Text(
            '${events.where((e) => e.boundary(selected)).length} 個當日事項 · ${events.where((e) => !e.boundary(selected)).length} 個期間進行中',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: NiuSpacing.lg),
        if (events.isEmpty)
          NiuEmptyState(
            title: query.isNotEmpty
                ? '找不到符合的事件'
                : '這${agenda ? '個月' : '天'}沒有校曆事件',
            message: query.isNotEmpty
                ? '試試「選課」「期中」等關鍵字，或調整分類。'
                : '可點選其他日期，或切換月份查看。',
            icon: CupertinoIcons.calendar,
            action: category == null
                ? null
                : TextButton(
                    onPressed: () => setState(() => category = null),
                    child: const Text('顯示全部類別'),
                  ),
          ),
        for (final section in sections.entries) ...[
          Semantics(
            header: true,
            child: Text(
              section.key,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const SizedBox(height: NiuSpacing.md),
          for (final e in section.value)
            Padding(
              padding: const EdgeInsets.only(bottom: NiuSpacing.md),
              child: AppCard(
                padding: EdgeInsets.zero,
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: NiuSpacing.lg,
                    vertical: NiuSpacing.sm,
                  ),
                  leading: Container(
                    width: 4,
                    decoration: BoxDecoration(
                      color: _color(e.category),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  title: Text(
                    e.title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    '${e.start}${e.start.compareTo(e.end) == 0 ? '' : ' ～ ${e.end}'}\n${calendarCategories[e.category]}',
                  ),
                  trailing: const Icon(CupertinoIcons.chevron_right, size: 16),
                  onTap: () => _details(e, data),
                ),
              ),
            ),
        ],
      ],
    );
  }

  void _details(CalendarEvent event, CalendarSnapshot data) {
    final source = data.sources[event.sourceId];
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      sheetAnimationStyle: MediaQuery.disableAnimationsOf(context)
          ? AnimationStyle.noAnimation
          : null,
      builder: (context) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            NiuSpacing.xxl,
            NiuSpacing.sm,
            NiuSpacing.xxl,
            NiuSpacing.xxxl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                calendarCategories[event.category] ?? event.category,
                style: TextStyle(color: _color(event.category)),
              ),
              const SizedBox(height: NiuSpacing.md),
              Text(
                event.title,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: NiuSpacing.lg),
              Text('${event.start} ～ ${event.end}'),
              if (event.note?.isNotEmpty ?? false) ...[
                const SizedBox(height: NiuSpacing.xl),
                Text(event.note!),
              ],
              const SizedBox(height: NiuSpacing.xxl),
              const Text('校方原文', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: NiuSpacing.sm),
              SelectableText(event.sourceText),
              const SizedBox(height: NiuSpacing.md),
              Text(
                '${data.sourceLabel} · 修訂 ${data.revision}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (source != null) ...[
                const SizedBox(height: NiuSpacing.xl),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(48, 48),
                  ),
                  onPressed: () => openPublicUrl(
                    context,
                    source.replace(fragment: 'page=${event.sourcePage ?? 1}'),
                  ),
                  icon: const Icon(CupertinoIcons.doc_text),
                  label: Text('查看校方 PDF · 第 ${event.sourcePage ?? 1} 頁'),
                ),
              ],
              const SizedBox(height: NiuSpacing.md),
              TextButton(
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                onPressed: () => Navigator.pop(context),
                child: const Text('完成'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Category identity colors are distinct from success/warning/error status tones.
Color _color(String category) => switch (category) {
  'registration' => Colors.blue,
  'exam' => Colors.red,
  'holiday' => Colors.green,
  'deadline' => Colors.pink,
  'semester' => Colors.purple,
  'academic' => Colors.indigo,
  'activity' => Colors.cyan,
  _ => Colors.orange,
};
