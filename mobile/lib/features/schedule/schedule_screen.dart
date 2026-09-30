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
      return Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              SizedBox(
                height: NiuSize.toolbar,
                child: IosPageHeader(
                  title: '我的課表',
                  actions: [
                    CircleIconButton(
                      icon: Icons.refresh,
                      tooltip: '更新課表',
                      onPressed: () => setState(() {
                        refreshing = true;
                        refreshOwner = owner;
                        refreshEpoch = session.coordinator.epoch;
                      }),
                    ),
                    CircleIconButton(
                      icon: Icons.more_horiz,
                      tooltip: '課表選項',
                      onPressed: () => showScheduleOptions(context, schedule),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ScheduleView(
                  schedule: schedule,
                  updatedAt: cached.fetchedAt,
                  offline: session.isOffline,
                ),
              ),
            ],
          ),
        ),
      );
    }
    final portal = AcademicPortalScreen(
      key: ValueKey((owner, session.coordinator.epoch)),
      session: session,
      webViewBuilder: widget.webViewBuilder,
      title: '我的課表',
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
          Material(
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(NiuSpacing.md),
                child: TextButton.icon(
                  icon: const Icon(Icons.history),
                  label: const Text('更新未完成？返回已儲存的課表'),
                  onPressed: () => setState(() => refreshing = false),
                ),
              ),
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
  showDragHandle: true,
  builder: (context) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(NiuSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('課表選項', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: NiuSpacing.lg),
          ScheduleExportBar(schedule: schedule),
        ],
      ),
    ),
  ),
);

class ScheduleView extends StatefulWidget {
  const ScheduleView({
    super.key,
    required this.schedule,
    this.updatedAt,
    this.offline = false,
    this.initialWeekday,
  });
  final ClassSchedule schedule;
  final DateTime? updatedAt;
  final bool offline;
  final int? initialWeekday;

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
    final today =
        DateTime.now().toUtc().add(const Duration(hours: 8)).weekday - 1;
    final lessons = lessonsByDay[scheduleWeekdays[selected]]!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        NiuSpacing.xl,
        NiuSpacing.sm,
        NiuSpacing.xl,
        NiuSpacing.xxxl,
      ),
      children: [
        Text(
          '${scheduleWeekdays[selected]}${selected == today ? '・今天' : ''}',
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: NiuSpacing.sm),
        Text(
          lessons.isEmpty
              ? '沒有安排課程'
              : '${lessons.length} 堂課・${lessons.first.start}–${lessons.last.end}',
          style: theme.textTheme.bodyMedium,
        ),
        if (widget.updatedAt != null) ...[
          const SizedBox(height: NiuSpacing.sm),
          RelativeUpdateText(updatedAt: widget.updatedAt!),
        ],
        if (widget.offline)
          const Padding(
            padding: EdgeInsets.only(top: NiuSpacing.sm),
            child: Text('離線中・顯示已儲存的課表'),
          ),
        const SizedBox(height: NiuSpacing.xxl),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: List.generate(7, (index) {
              final hasLessons =
                  lessonsByDay[scheduleWeekdays[index]]!.isNotEmpty;
              final active = selected == index;
              return Padding(
                padding: const EdgeInsets.only(right: NiuSpacing.sm),
                child: Semantics(
                  selected: active,
                  button: true,
                  excludeSemantics: true,
                  onTap: () => setState(() => selected = index),
                  label:
                      '${scheduleWeekdays[index]}${index == today ? '，今天' : ''}，${hasLessons ? '有課' : '沒有課'}',
                  child: Tooltip(
                    message: scheduleWeekdays[index],
                    child: Material(
                      color: active
                          ? theme.colorScheme.primary
                          : NiuColors.of(context).surfaceSecondary,
                      borderRadius: BorderRadius.circular(NiuRadius.control),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(NiuRadius.control),
                        onTap: () => setState(() => selected = index),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            minWidth: 48,
                            minHeight: 64,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: NiuSpacing.md,
                              vertical: 10,
                            ),
                            child: Column(
                              children: [
                                Text(
                                  '一二三四五六日'[index],
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    color: active
                                        ? theme.colorScheme.onPrimary
                                        : theme.colorScheme.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Container(
                                  width: 5,
                                  height: 5,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: hasLessons
                                        ? (active
                                              ? theme.colorScheme.onPrimary
                                              : theme.colorScheme.primary)
                                        : Colors.transparent,
                                  ),
                                ),
                                if (index == today)
                                  Text(
                                    '今天',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: active
                                          ? theme.colorScheme.onPrimary
                                          : theme.colorScheme.primary,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 28),
        if (lessons.isEmpty)
          AppCard(
            child: Column(
              children: [
                Icon(
                  Icons.wb_sunny_outlined,
                  size: 36,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: NiuSpacing.lg),
                Text(
                  selected == today ? '今天沒有課' : '這天沒有課',
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: NiuSpacing.sm),
                const Text('留點時間給自己，好好休息吧。'),
              ],
            ),
          ),
        ...lessons.map(
          (lesson) => Padding(
            padding: const EdgeInsets.only(bottom: NiuSpacing.lg),
            child: _LessonTile(lesson: lesson),
          ),
        ),
      ],
    );
  }
}

class _LessonTile extends StatelessWidget {
  const _LessonTile({required this.lesson});
  final ScheduleLesson lesson;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final compact = MediaQuery.sizeOf(context).width < 360 && scale > 1.5;
    final time = Text(
      '${lesson.start}–${lesson.end}',
      style: theme.textTheme.labelLarge,
    );
    final card = Container(
      decoration: BoxDecoration(
        color: NiuColors.of(context).cardSurface,
        borderRadius: BorderRadius.circular(NiuRadius.card),
      ),
      padding: const EdgeInsets.all(NiuSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (compact) ...[time, const SizedBox(height: NiuSpacing.md)],
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: NiuColors.of(context).infoSoft,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              lesson.periodLabel,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(height: NiuSpacing.md),
          Text(
            lesson.name,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          if (lesson.teacher.isNotEmpty) ...[
            const SizedBox(height: NiuSpacing.lg),
            _detail(context, Icons.person_outline, lesson.teacher),
          ],
          if (lesson.room.isNotEmpty) ...[
            const SizedBox(height: NiuSpacing.sm),
            _detail(context, Icons.location_on_outlined, lesson.room),
          ],
        ],
      ),
    );
    if (compact) return card;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: scale > 1.5 ? 86 : 62,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(lesson.start, style: theme.textTheme.labelLarge),
              const SizedBox(height: 6),
              Text(
                lesson.end,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: card),
      ],
    );
  }

  Widget _detail(BuildContext context, IconData icon, String text) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(
        icon,
        size: 18,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      const SizedBox(width: 6),
      Expanded(child: Text(text, style: Theme.of(context).textTheme.bodySmall)),
    ],
  );
}
