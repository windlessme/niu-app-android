import 'package:flutter/material.dart';
import '../../core/web/academic_portal_screen.dart';
import 'schedule_export.dart';
import '../../core/session/campus_session.dart';
import '../../shared/shared.dart';
import 'schedule_presentation.dart';

class SchedulePeriod {
  const SchedulePeriod(this.label, this.time, this.courses);
  final String label;
  final String time;
  final Map<String, String> courses;
}

class ClassSchedule {
  const ClassSchedule(this.days, this.periods);
  final List<String> days;
  final List<SchedulePeriod> periods;

  /// Supports both school table layouts: separate and combined period/time.
  factory ClassSchedule.fromRows(List<List<String>> rows) {
    if (rows.isEmpty) throw const FormatException('找不到課表');
    final start = rows.first.indexWhere((cell) => cell.contains('星期'));
    if (start < 1) throw const FormatException('課表欄位不符');
    final days = rows.first.skip(start).map((e) => e.trim()).toList();
    final periods = <SchedulePeriod>[];
    for (final row in rows.skip(1)) {
      if (row.length <= start) continue;
      final parts = row.first
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      if (parts.isEmpty) continue;
      final time = start >= 2 ? row[1].trim() : parts.skip(1).join('\n');
      periods.add(
        SchedulePeriod(parts.first, time, {
          for (var i = 0; i < days.length && i + start < row.length; i++)
            if (row[i + start].trim().isNotEmpty)
              days[i]: row[i + start].trim(),
        }),
      );
    }
    return ClassSchedule(days, periods);
  }
}

const scheduleExtractScript = r'''
(() => {
  const docs = [];
  function collect(w) {
    try { docs.push(w.document); for (let i=0;i<w.frames.length;i++) collect(w.frames[i]); } catch (_) {}
  }
  collect(window);
  const table = docs.map(d => d.getElementById('table2')).find(t => t && (t.innerText || '').includes('星期'));
  if (!table) return null;
  return JSON.stringify(Array.from(table.querySelectorAll('tr'), row =>
    Array.from(row.querySelectorAll('td,th'), cell => cell.innerText.trim())));
})()
''';

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key, this.session, this.webViewBuilder});
  final CampusSession? session;
  final Widget Function(Widget Function() create)? webViewBuilder;

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  late final session = widget.session ?? CampusSession.instance;
  bool refreshing = false;
  String? refreshOwner;
  int? refreshEpoch;
  List<List<String>>? parsedRows;
  ClassSchedule? parsedSchedule;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: session,
    builder: (context, _) => buildSchedule(context),
  );

  Widget buildSchedule(BuildContext context) {
    final owner = session.account;
    final cached = session.cachedSchedule;
    final fetching =
        refreshing &&
        refreshOwner == owner &&
        refreshEpoch == session.coordinator.epoch;
    if (!fetching && cached != null && cached.account == owner) {
      if (!identical(parsedRows, cached.rows)) {
        parsedSchedule = ClassSchedule.fromRows(cached.rows);
        parsedRows = cached.rows;
      }
      final schedule = parsedSchedule!;
      return NiuScrollPage(
        title: '課表',
        large: true,
        showBack: false,
        actions: [
          NiuIconButton(
            icon: NiuIcons.refresh,
            tooltip: '更新課表',
            onPressed: () => setState(() {
              refreshing = true;
              refreshOwner = owner;
              refreshEpoch = session.coordinator.epoch;
            }),
          ),
          NiuIconButton(
            icon: NiuIcons.more,
            tooltip: '課表選項',
            onPressed: () => showScheduleOptions(context, schedule),
          ),
        ],
        children: [
          ScheduleView(
            schedule: schedule,
            updatedAt: cached.fetchedAt,
            offline: session.isOffline,
            embedded: true,
          ),
        ],
      );
    }
    final portal = AcademicPortalScreen(
      key: ValueKey((owner, session.coordinator.epoch)),
      session: session,
      webViewBuilder: widget.webViewBuilder,
      title: '課表',
      referer: Uri.parse(
        'https://acade.niu.edu.tw/NIU/Application/TKE/TKE22/TKE2240_01.aspx',
      ),
      target: Uri.parse(
        'https://acade.niu.edu.tw/NIU/Application/TKE/TKE22/TKE2240_01.aspx',
      ),
      prepareScript: scheduleQueryScript,
      extractScript: scheduleExtractScript,
      onSnapshot: (value, epoch) async {
        final rows = (value as List)
            .map((r) => (r as List).map((v) => v.toString()).toList())
            .toList();
        ClassSchedule.fromRows(rows);
        if (owner != null) {
          await session.cacheScheduleRows(rows, epoch: epoch, owner: owner);
          if (mounted &&
              session.account == owner &&
              session.coordinator.epoch == epoch) {
            setState(() => refreshing = false);
          }
        }
      },
      snapshotBuilder: (_, value) => ScheduleView(
        schedule: ClassSchedule.fromRows(
          (value as List)
              .map((r) => (r as List).map((v) => v.toString()).toList())
              .toList(),
        ),
      ),
    );
    if (fetching && cached != null && cached.account == owner) {
      return Column(
        children: [
          Expanded(child: portal),
          NiuBottomBar(
            child: OutlinedButton.icon(
              icon: const Icon(NiuIcons.history),
              label: const Text('先看已保存的課表'),
              onPressed: () => setState(() => refreshing = false),
            ),
          ),
        ],
      );
    }
    return portal;
  }
}

const scheduleQueryScript = r'''
(() => {
  function query(w) {
    try {
      const d = w.document;
      const url = new URL(d.location.href);
      if (url.hostname === 'acade.niu.edu.tw' && /\/TKE2240_01\.aspx$/i.test(url.pathname)) {
        if (d.readyState !== 'complete') return false;
        const button = d.querySelector('input#QUERY_BTN3');
        if (!button || button.disabled) return false;
        const run = w.__niuAcademicRun;
        if (!run) return false;
        const key = 'niu.schedule.query.' + url.pathname;
        let state = d.__niuScheduleQuery;
        if (!state || state.run !== run) {
          let previous;
          try { previous = JSON.parse(w.sessionStorage.getItem(key)); } catch (_) {}
          state = d.__niuScheduleQuery = {
            run, phase: previous && previous.run === run ? 'settled' : 'idle',
            response: !!(previous && previous.run === run), stable: null,
          };
          if (state.response) w.sessionStorage.removeItem(key);
        }
        const manager = w.Sys && w.Sys.WebForms && w.Sys.WebForms.PageRequestManager.getInstance();
        if (manager && manager.get_isInAsyncPostBack()) return false;
        if (state.phase === 'idle') {
          state.phase = 'pending';
          // This receipt belongs to this load attempt, not a previous refresh or
          // account. Only a replacement document may consume a postback receipt.
          w.sessionStorage.setItem(key, JSON.stringify({run}));
          w.addEventListener('beforeunload', () => { state.leaving = true; });
          if (manager) manager.add_endRequest(() => {
            state.response = true;
            state.phase = 'settled';
            state.stable = null;
            w.sessionStorage.removeItem(key);
          });
          const table = d.getElementById('table2');
          const before = table && table.innerHTML;
          button.click();
          // Some portal variants render synchronously instead of posting back.
          const after = d.getElementById('table2');
          if (after && (after !== table || after.innerHTML !== before)) {
            state.phase = 'settled';
            state.response = true;
            w.sessionStorage.removeItem(key);
          }
          return false;
        }
        if (state.phase !== 'settled' || state.leaving) return false;
        const table = d.getElementById('table2');
        if (!table || !(table.innerText || '').includes('星期')) return false;
        const rows = Array.from(table.querySelectorAll('tr'), row =>
          Array.from(row.querySelectorAll('td,th'), cell => cell.innerText.trim()));
        if (!rows.length || !rows[0].some(cell => cell.includes('星期'))) return false;
        // Empty timetables are valid after a confirmed query response, including
        // header-only responses. Require two identical reads of the settled DOM.
        const value = JSON.stringify(rows);
        if (state.stable !== value) { state.stable = value; return false; }
        return state.response;
      }
      for (let i=0;i<w.frames.length;i++) { if (query(w.frames[i])) return true; }
    } catch (_) {}
    return false;
  }
  return query(window);
})()
''';

Future<void> showScheduleOptions(
  BuildContext context,
  ClassSchedule schedule,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  builder: (context) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        NiuSpacing.gutter,
        0,
        NiuSpacing.gutter,
        NiuSpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('課表選項', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: NiuSpacing.xs),
          Text(
            '設定學期日期後，可以匯出到行事曆、開啟上課提醒，並更新桌面小工具。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: NiuSpacing.lg),
          ScheduleExportBar(schedule: schedule),
        ],
      ),
    ),
  ),
);

const _weekdayShort = '一二三四五六日';

class ScheduleView extends StatefulWidget {
  const ScheduleView({
    super.key,
    required this.schedule,
    this.updatedAt,
    this.offline = false,
    this.initialWeekday,
    this.embedded = false,
  });
  final ClassSchedule schedule;
  final DateTime? updatedAt;
  final bool offline;
  final int? initialWeekday;

  /// Embedded views render inside a parent scroll view instead of their own.
  final bool embedded;

  @override
  State<ScheduleView> createState() => _ScheduleViewState();
}

class _ScheduleViewState extends State<ScheduleView> {
  late Map<String, List<ScheduleLesson>> lessonsByDay = _parseLessons();

  Map<String, List<ScheduleLesson>> _parseLessons() => {
    for (final day in scheduleWeekdays)
      day: scheduleLessons(widget.schedule, day),
  };

  @override
  void didUpdateWidget(covariant ScheduleView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.schedule, widget.schedule)) {
      lessonsByDay = _parseLessons();
    }
  }

  late int selected =
      (widget.initialWeekday ??
          DateTime.now().toUtc().add(const Duration(hours: 8)).weekday) -
      1;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now().toUtc().add(const Duration(hours: 8));
    final today = now.weekday - 1;
    final minute = now.hour * 60 + now.minute;
    final lessons = lessonsByDay[scheduleWeekdays[selected]]!;
    final children = [
      _DayPicker(
        selected: selected,
        today: today,
        hasLessons: [
          for (final day in scheduleWeekdays) lessonsByDay[day]!.isNotEmpty,
        ],
        onSelected: (index) => setState(() => selected = index),
      ),
      const SizedBox(height: NiuSpacing.xxl),
      Semantics(
        header: true,
        child: Text(
          selected == today
              ? '今天・${scheduleWeekdays[selected]}'
              : scheduleWeekdays[selected],
          style: theme.textTheme.titleLarge,
        ),
      ),
      const SizedBox(height: 2),
      Text(
        lessons.isEmpty
            ? '沒有課'
            : '${lessons.length} 堂課・${lessons.first.start}–${lessons.last.end}',
        style: theme.textTheme.bodySmall?.copyWith(
          fontFeatures: tabularFigures,
        ),
      ),
      const SizedBox(height: NiuSpacing.lg),
      if (lessons.isEmpty)
        NiuCard(
          child: NiuEmpty(
            padding: const EdgeInsets.symmetric(
              vertical: NiuSpacing.xxl,
              horizontal: NiuSpacing.lg,
            ),
            icon: NiuIcons.sunny,
            tone: NiuTone.warning,
            title: selected == today ? '今天沒有課' : '這天沒有課',
            message: '留點時間給自己。',
          ),
        ),
      for (final lesson in lessons)
        Padding(
          padding: const EdgeInsets.only(bottom: NiuSpacing.md),
          child: _LessonTile(
            lesson: lesson,
            current:
                selected == today &&
                _minutes(lesson.start) != null &&
                _minutes(lesson.end) != null &&
                _minutes(lesson.start)! <= minute &&
                minute < _minutes(lesson.end)!,
          ),
        ),
      if (widget.updatedAt != null || widget.offline) ...[
        const SizedBox(height: NiuSpacing.md),
        NiuSyncStatus(updatedAt: widget.updatedAt, offline: widget.offline),
      ],
    ];
    if (widget.embedded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        NiuSpacing.gutter,
        NiuSpacing.lg,
        NiuSpacing.gutter,
        NiuSpacing.huge,
      ),
      children: children,
    );
  }
}

int? _minutes(String clock) {
  final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(clock);
  if (match == null) return null;
  return int.parse(match[1]!) * 60 + int.parse(match[2]!);
}

class _DayPicker extends StatelessWidget {
  const _DayPicker({
    required this.selected,
    required this.today,
    required this.hasLessons,
    required this.onSelected,
  });
  final int selected, today;
  final List<bool> hasLessons;
  final ValueChanged<int> onSelected;
  @override
  Widget build(BuildContext context) {
    final large = MediaQuery.textScalerOf(context).scale(16) > 22;
    final days = [
      for (var i = 0; i < 7; i++)
        _DayChip(
          index: i,
          active: i == selected,
          today: i == today,
          hasLessons: hasLessons[i],
          onTap: () => onSelected(i),
        ),
    ];
    if (large) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final day in days)
              Padding(
                padding: const EdgeInsets.only(right: NiuSpacing.sm),
                child: SizedBox(width: 64, child: day),
              ),
          ],
        ),
      );
    }
    return Row(
      children: [
        for (final (i, day) in days.indexed) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(child: day),
        ],
      ],
    );
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({
    required this.index,
    required this.active,
    required this.today,
    required this.hasLessons,
    required this.onTap,
  });
  final int index;
  final bool active, today, hasLessons;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = NiuColors.of(context);
    final fg = active ? colors.onAccent : colors.ink;
    return Semantics(
      selected: active,
      button: true,
      excludeSemantics: true,
      onTap: onTap,
      label:
          '${scheduleWeekdays[index]}${today ? '，今天' : ''}，${hasLessons ? '有課' : '沒有課'}',
      child: Tooltip(
        message: scheduleWeekdays[index],
        child: Material(
          color: active ? colors.accent : colors.surface,
          borderRadius: BorderRadius.circular(NiuRadius.lg),
          child: InkWell(
            borderRadius: BorderRadius.circular(NiuRadius.lg),
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 64),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      today ? '今天' : '週${_weekdayShort[index]}',
                      maxLines: 1,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: active
                            ? colors.onAccent.withValues(alpha: .8)
                            : today
                            ? colors.accent
                            : colors.inkTertiary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _weekdayShort[index],
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: fg,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: !hasLessons
                            ? Colors.transparent
                            : active
                            ? colors.onAccent
                            : colors.accent,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LessonTile extends StatelessWidget {
  const _LessonTile({required this.lesson, this.current = false});
  final ScheduleLesson lesson;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = NiuColors.of(context);
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final compact = MediaQuery.sizeOf(context).width < 360 && scale > 1.5;
    final card = NiuCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: NiuSpacing.sm,
            runSpacing: NiuSpacing.xs,
            children: [
              if (current)
                const NiuBadge(label: '上課中', tone: NiuTone.accent, solid: true),
              NiuBadge(label: lesson.periodLabel, tone: NiuTone.accent),
              if (compact) NiuBadge(label: '${lesson.start}–${lesson.end}'),
            ],
          ),
          const SizedBox(height: NiuSpacing.sm),
          Text(
            lesson.name,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          if (lesson.teacher.isNotEmpty || lesson.room.isNotEmpty)
            const SizedBox(height: NiuSpacing.sm),
          if (lesson.room.isNotEmpty)
            _detail(context, NiuIcons.location, lesson.room),
          if (lesson.teacher.isNotEmpty)
            _detail(context, NiuIcons.person, lesson.teacher),
        ],
      ),
    );
    if (compact) return card;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: scale > 1.5 ? 76 : 52,
            child: Padding(
              padding: const EdgeInsets.only(top: NiuSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    lesson.start,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: current ? colors.accent : colors.ink,
                      fontFeatures: tabularFigures,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    lesson.end,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontFeatures: tabularFigures,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: NiuSpacing.sm),
          Expanded(child: card),
        ],
      ),
    );
  }

  Widget _detail(BuildContext context, IconData icon, String text) => Padding(
    padding: const EdgeInsets.only(top: 2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 16, color: NiuColors.of(context).inkTertiary),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.bodySmall),
        ),
      ],
    ),
  );
}
