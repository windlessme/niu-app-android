import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/analytics/app_analytics.dart';
import '../../core/session/campus_session.dart';
import '../../shared/shared.dart';
import '../schedule/custom_course_editor.dart';
import '../schedule/custom_courses.dart';
import '../schedule/schedule_models.dart';
import '../schedule/schedule_presentation.dart';
import '../schedule/schedule_week_view.dart';
import 'group_availability.dart';
import 'my_schedule_code_screen.dart';
import 'schedule_exchange_store.dart';
import 'schedule_scan_screen.dart';
import 'schedule_share.dart';

/// The signed-in student's school timetable, when one is saved.
ClassSchedule? exchangeSchoolSchedule(CampusSession session) {
  final cached = session.cachedSchedule;
  if (cached == null || cached.account != session.account) return null;
  try {
    return ClassSchedule.fromRows(cached.rows);
  } on FormatException {
    return null;
  }
}

/// The timetable as the student sees it, custom courses included, so their
/// own commitments count as busy. Compared on this device only.
ClassSchedule? exchangeShownSchedule(CampusSession session) =>
    exchangeSchoolSchedule(session)?.withCustomCourses(
      CustomCourseStore.instance.coursesFor(session.account),
      taipeiToday(),
    );

ScheduleSharePayload? myComparison(
  ClassSchedule? shown,
  ScheduleShareTerm term,
) {
  if (shown == null || term != ScheduleShareTerm.containing(DateTime.now())) {
    return null;
  }
  return ScheduleSharePayload.fromSchedule(
    shown,
    shareId: ScheduleSharePayload.newShareId(),
    term: term,
    nickname: '我',
    createdAt: DateTime.now(),
    withCustom: true,
  );
}

/// [base]'s free rows with [others], keeping only rows between the first and
/// last period anyone has class: free evenings after everyone's last class
/// are not worth a row.
Set<int> commonFreeSlots(
  ScheduleSharePayload base,
  List<ScheduleSharePayload> others,
) {
  final everyone = [base, ...others];
  final busy = [
    for (final (row, p) in base.periods.indexed)
      if (base.days.any(
        (day) => everyone.any((e) => e.busy(day, p.start, p.end)),
      ))
        row,
  ];
  if (busy.isEmpty) return const {};
  final first = busy.first, last = busy.last;
  return {
    for (final key in base.freeSlots(others))
      if (key % 100 >= first && key % 100 <= last) key,
  };
}

/// 「週二・第 3–4 節・10:10–12:00」 for each run of free periods.
List<String> freeTimeLines(ScheduleSharePayload base, Set<int> keys) {
  String clock(int m) => '${m ~/ 60}:${(m % 60).toString().padLeft(2, '0')}';
  final lines = <String>[];
  for (final day in base.days) {
    final rows = [
      for (var row = 0; row < base.periods.length; row++)
        if (keys.contains(day * 100 + row)) row,
    ];
    for (var i = 0; i < rows.length;) {
      var j = i;
      while (j + 1 < rows.length && rows[j + 1] == rows[j] + 1) {
        j++;
      }
      final from = base.periods[rows[i]], to = base.periods[rows[j]];
      final a = schedulePeriodNumber(from.id), b = schedulePeriodNumber(to.id);
      lines.add(
        '週${'一二三四五六日'[day]}・第 ${a == b ? a : '$a–$b'} 節・${clock(from.start)}–${clock(to.end)}',
      );
      i = j + 1;
    }
  }
  return lines;
}

class ScheduleExchangeScreen extends StatefulWidget {
  const ScheduleExchangeScreen({super.key, this.session, this.store});
  final CampusSession? session;
  final ScheduleExchangeStore? store;
  @override
  State<ScheduleExchangeScreen> createState() => _ScheduleExchangeScreenState();
}

class _ScheduleExchangeScreenState extends State<ScheduleExchangeScreen> {
  late final session = widget.session ?? CampusSession.instance;
  late final store = widget.store ?? ScheduleExchangeStore.instance;

  @override
  void initState() {
    super.initState();
    session.addListener(_follow);
    _follow();
  }

  void _follow() {
    store.bind(session.account);
    unawaited(CustomCourseStore.instance.load(session.account));
  }

  @override
  void dispose() {
    session.removeListener(_follow);
    super.dispose();
  }

  ScheduleShareTerm get term => ScheduleShareTerm.containing(DateTime.now());

  Future<void> scan() async {
    final saved = await Navigator.of(context).push<ExchangedSchedule>(
      MaterialPageRoute(
        builder: (_) => ScheduleScanScreen(session: session, store: store),
      ),
    );
    if (saved == null || !mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已加入「${saved.displayName}」')));
    open(saved.id);
  }

  void open(String id) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) =>
          ClassmateScheduleScreen(id: id, session: session, store: store),
    ),
  );

  Future<void> compare([Set<String> initial = const {}]) async {
    final ids = await pickClassmates(context, store, term, initial);
    if (ids == null || ids.isEmpty || !mounted) return;
    AppAnalytics.instance.event('schedule_exchange', {
      'action': 'compare',
      'count': ids.length + 1,
    });
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            GroupCompareScreen(ids: ids, session: session, store: store),
      ),
    );
  }

  Future<void> delete(ExchangedSchedule entry) async {
    if (await confirmDeleteClassmate(context, entry) != true || !mounted) {
      return;
    }
    final account = session.account;
    if (account == null || !await store.delete(account, entry.id)) {
      if (mounted) showExchangeError(context, '無法刪除，請稍後再試。');
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([session, store, CustomCourseStore.instance]),
    builder: (context, _) {
      final account = session.account;
      final school = exchangeSchoolSchedule(session);
      final now = DateTime.now();
      final ready = store.isReadyFor(account);
      final classmates = ready ? sortedClassmates(store.schedules, now) : [];
      final comparable = classmates.where((e) => e.payload.term == term);
      final theme = Theme.of(context);
      return NiuScrollPage(
        title: '課表交換',
        children: [
          if (store.status == ExchangeStatus.unreadable && account != null)
            NiuBanner(
              tone: NiuTone.error,
              message: '同學的課表無法開啟，可能是裝置還原或資料遺失。',
              actionLabel: '清除',
              onAction: () async {
                final ok = await confirm(
                  context,
                  title: '清除這個帳號的同學課表？',
                  message: '清除後無法復原。',
                  action: '清除',
                );
                if (ok) await store.resetUnreadable(account);
              },
            )
          else if (!ready)
            const Padding(
              padding: EdgeInsets.only(top: NiuSpacing.huge),
              child: NiuLoading(message: '正在讀取同學的課表'),
            )
          else ...[
            if (classmates.isEmpty)
              NiuCard(
                child: NiuEmpty(
                  padding: const EdgeInsets.symmetric(vertical: NiuSpacing.lg),
                  icon: Icons.people_alt_rounded,
                  title: '和同學交換課表',
                  message: '兩個人都打開「課表交換」，一個人按「掃描」，另一個人按「我的 QR Code」。',
                ),
              ),
            const SizedBox(height: NiuSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: scan,
                    icon: const Icon(NiuIcons.attendance),
                    label: const Text('掃描'),
                  ),
                ),
                const SizedBox(width: NiuSpacing.md),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: school == null
                        ? null
                        : () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => MyScheduleCodeScreen(
                                session: session,
                                store: store,
                              ),
                            ),
                          ),
                    icon: const Icon(NiuIcons.qr),
                    label: const Text('我的 QR Code'),
                  ),
                ),
              ],
            ),
            if (school == null) ...[
              const SizedBox(height: NiuSpacing.sm),
              NiuBanner(
                message: '你的課表載入後，才能產生 QR Code 和比對空堂。',
                actionLabel: '開啟課表',
                onAction: () => GoRouter.of(context).go('/schedule'),
              ),
            ],
            if (comparable.isNotEmpty && school != null) ...[
              const SizedBox(height: NiuSpacing.lg),
              NiuGroup(
                children: [
                  NiuRow(
                    icon: Icons.groups_rounded,
                    hue: NiuHue.green,
                    title: '找共同空堂',
                    subtitle: '選幾位同學，找大家都沒課的時間',
                    onTap: compare,
                  ),
                ],
              ),
            ],
            if (classmates.isNotEmpty)
              NiuSection(
                title: '同學的課表',
                child: NiuGroup(
                  children: [
                    for (final entry in classmates)
                      NiuRow(
                        leading: ClassmateAvatar(entry.displayName),
                        title: entry.displayName,
                        subtitle: classmateDetail(entry, now),
                        onTap: () => open(entry.id),
                        trailing: PopupMenuButton<void>(
                          tooltip: '更多',
                          icon: const Icon(NiuIcons.more),
                          itemBuilder: (_) => [
                            PopupMenuItem(
                              onTap: () => delete(entry),
                              child: const Text('刪除'),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: NiuSpacing.md),
            Text('同學的課表只加密存在這台裝置，不會上傳。', style: theme.textTheme.bodySmall),
            if (session.isDemo && school != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => addDemoClassmates(store, account!, school),
                  icon: const Icon(NiuIcons.add),
                  label: const Text('加入示範同學'),
                ),
              ),
          ],
        ],
      );
    },
  );
}

/// Current-term entries first, then by name.
List<ExchangedSchedule> sortedClassmates(
  List<ExchangedSchedule> list,
  DateTime now,
) => [...list]
  ..sort((a, b) {
    final expired = (a.isExpired(now) ? 1 : 0) - (b.isExpired(now) ? 1 : 0);
    return expired != 0 ? expired : a.displayName.compareTo(b.displayName);
  });

String classmateDetail(ExchangedSchedule entry, DateTime now) {
  final payload = entry.payload;
  if (entry.isExpired(now)) return '${payload.term.title}・已過期';
  final extras = [if (payload.hasRooms) '教室', if (payload.hasTeachers) '教師'];
  return [
    '${payload.courseCount} 門課',
    if (payload.term != ScheduleShareTerm.containing(now)) payload.term.title,
    if (extras.isNotEmpty) '含${extras.join('、')}',
  ].join('・');
}

class ClassmateAvatar extends StatelessWidget {
  const ClassmateAvatar(
    this.name, {
    super.key,
    this.me = false,
    this.size = 40,
  });
  final String name;
  final bool me;
  final double size;
  @override
  Widget build(BuildContext context) {
    final hue = me ? NiuHue.blue : NiuHue.purple;
    return ExcludeSemantics(
      child: CircleAvatar(
        radius: size / 2,
        backgroundColor: hue.background(context),
        foregroundColor: hue.foreground(context),
        child: Text(
          name.characters.take(1).toString(),
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: size * .42),
        ),
      ),
    );
  }
}

void showExchangeError(BuildContext context, String message) =>
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));

Future<bool> confirm(
  BuildContext context, {
  required String title,
  String? message,
  required String action,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: message == null ? null : Text(message),
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
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;

Future<bool> confirmDeleteClassmate(
  BuildContext context,
  ExchangedSchedule entry,
) => confirm(context, title: '刪除「${entry.displayName}」的課表？', action: '刪除');

/// Classmates of [term] to compare with the student's own timetable.
Future<Set<String>?> pickClassmates(
  BuildContext context,
  ScheduleExchangeStore store,
  ScheduleShareTerm term,
  Set<String> initial,
) {
  final classmates = [...store.schedules.where((e) => e.payload.term == term)]
    ..sort((a, b) => a.displayName.compareTo(b.displayName));
  final selected = {
    ...initial.where((id) => classmates.any((e) => e.id == id)),
  };
  return showModalBottomSheet<Set<String>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheet) => StatefulBuilder(
      builder: (sheet, setSheet) {
        final all = selected.length == classmates.length;
        final theme = Theme.of(sheet);
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(sheet).height * .8,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: NiuSpacing.gutter,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '和誰一起比對？',
                          style: theme.textTheme.titleLarge,
                        ),
                      ),
                      TextButton(
                        onPressed: () => setSheet(() {
                          all
                              ? selected.clear()
                              : selected.addAll(classmates.map((e) => e.id));
                        }),
                        child: Text(all ? '全不選' : '全選'),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: NiuSpacing.gutter,
                  ),
                  child: Text(
                    '只能比對${term.title}的課表，你的課表一定會包含在內。',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                const SizedBox(height: NiuSpacing.sm),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final entry in classmates)
                        CheckboxListTile(
                          value: selected.contains(entry.id),
                          onChanged: (on) => setSheet(
                            () => on == true
                                ? selected.add(entry.id)
                                : selected.remove(entry.id),
                          ),
                          secondary: ClassmateAvatar(entry.displayName),
                          title: Text(entry.displayName),
                          controlAffinity: ListTileControlAffinity.trailing,
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    NiuSpacing.gutter,
                    NiuSpacing.md,
                    NiuSpacing.gutter,
                    NiuSpacing.lg,
                  ),
                  child: FilledButton(
                    onPressed: selected.isEmpty
                        ? null
                        : () => Navigator.pop(sheet, {...selected}),
                    child: Text(
                      selected.isEmpty
                          ? '請至少選一位同學'
                          : '開始比對（${selected.length + 1} 人）',
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

/// Height the week grid may fill below a page's header card.
double _gridHeight(BuildContext context) =>
    MediaQuery.sizeOf(context).height -
    MediaQuery.paddingOf(context).vertical -
    330;

class ClassmateScheduleScreen extends StatefulWidget {
  const ClassmateScheduleScreen({
    super.key,
    required this.id,
    required this.session,
    required this.store,
  });
  final String id;
  final CampusSession session;
  final ScheduleExchangeStore store;
  @override
  State<ClassmateScheduleScreen> createState() =>
      _ClassmateScheduleScreenState();
}

class _ClassmateScheduleScreenState extends State<ClassmateScheduleScreen> {
  bool marksFree = true;
  ExchangedSchedule? entry;
  ClassSchedule? table;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      widget.session,
      widget.store,
      CustomCourseStore.instance,
    ]),
    builder: (context, _) {
      final found = widget.store.isReadyFor(widget.session.account)
          ? widget.store.schedules.where((e) => e.id == widget.id).firstOrNull
          : null;
      if (found == null) {
        return const NiuScrollPage(
          title: '同學的課表',
          children: [
            NiuEmpty(icon: Icons.person_off_rounded, title: '找不到這份課表'),
          ],
        );
      }
      if (!identical(found, entry)) {
        entry = found;
        table = found.payload.toClassSchedule();
      }
      final payload = found.payload;
      final now = DateTime.now();
      final shown = exchangeShownSchedule(widget.session);
      final mine = myComparison(shown, payload.term);
      final free = mine == null || !marksFree
          ? null
          : commonFreeSlots(payload, [mine]);
      final theme = Theme.of(context);
      return NiuScrollPage(
        title: '${found.displayName} 的課表',
        actions: [
          NiuIconButton(
            icon: Icons.delete_outline_rounded,
            tooltip: '刪除',
            onPressed: () async {
              final account = widget.session.account;
              if (account == null ||
                  !await confirmDeleteClassmate(context, found) ||
                  !context.mounted) {
                return;
              }
              if (await widget.store.delete(account, found.id)) {
                if (context.mounted) Navigator.pop(context);
              } else if (context.mounted) {
                showExchangeError(context, '無法刪除，請稍後再試。');
              }
            },
          ),
        ],
        children: [
          NiuCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    ClassmateAvatar(found.displayName),
                    const SizedBox(width: NiuSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            found.displayName,
                            style: theme.textTheme.titleMedium,
                          ),
                          Text(
                            found.isExpired(now)
                                ? '${payload.term.title}・已過期'
                                : '${payload.term.title}・${payload.includedFields}',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: NiuSpacing.sm),
                if (mine != null) ...[
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: marksFree,
                    onChanged: (v) => setState(() => marksFree = v),
                    title: const Text('標出我們都沒課的時間'),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          marksFree ? '綠色是你們都沒課的時間，你的自訂課程也算在內。' : '',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          final ids = await pickClassmates(
                            context,
                            widget.store,
                            payload.term,
                            {found.id},
                          );
                          if (ids == null || ids.isEmpty || !context.mounted) {
                            return;
                          }
                          await Navigator.of(context).pushReplacement(
                            MaterialPageRoute<void>(
                              builder: (_) => GroupCompareScreen(
                                ids: ids,
                                session: widget.session,
                                store: widget.store,
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.person_add_alt_rounded),
                        label: const Text('加人比對'),
                      ),
                    ],
                  ),
                ] else
                  Text(
                    shown == null
                        ? '你的課表載入後，就能標出你們都沒課的時間。'
                        : '這份課表不是本學期的，無法和你的課表比對。',
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ),
          ),
          const SizedBox(height: NiuSpacing.xl),
          ScheduleWeekView(
            schedule: table!,
            now: now.toUtc().add(const Duration(hours: 8)),
            height: _gridHeight(context),
            freeSlots: free,
          ),
          if (free != null) _FreeTimeList(lines: freeTimeLines(payload, free)),
        ],
      );
    },
  );
}

class GroupCompareScreen extends StatefulWidget {
  const GroupCompareScreen({
    super.key,
    required this.ids,
    required this.session,
    required this.store,
  });
  final Set<String> ids;
  final CampusSession session;
  final ScheduleExchangeStore store;
  @override
  State<GroupCompareScreen> createState() => _GroupCompareScreenState();
}

class _GroupCompareScreenState extends State<GroupCompareScreen> {
  late Set<String> ids = widget.ids;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      widget.session,
      widget.store,
      CustomCourseStore.instance,
    ]),
    builder: (context, _) {
      final term = ScheduleShareTerm.containing(DateTime.now());
      final classmates = widget.store.isReadyFor(widget.session.account)
          ? ([
              ...widget.store.schedules.where(
                (e) => ids.contains(e.id) && e.payload.term == term,
              ),
            ]..sort((a, b) => a.displayName.compareTo(b.displayName)))
          : <ExchangedSchedule>[];
      final shown = exchangeShownSchedule(widget.session);
      final mine = myComparison(shown, term);
      final theme = Theme.of(context);
      if (shown == null || mine == null || classmates.isEmpty) {
        return const NiuScrollPage(
          title: '共同空堂',
          children: [
            NiuEmpty(
              icon: Icons.groups_rounded,
              title: '沒有可以比對的課表',
              message: '請確認你的課表已載入，並至少選一位本學期的同學。',
            ),
          ],
        );
      }
      final names = ['我', ...classmates.map((e) => e.displayName)];
      final group = GroupAvailability(mine, [
        mine,
        ...classmates.map((e) => e.payload),
      ], names);
      return NiuScrollPage(
        title: '共同空堂',
        children: [
          NiuCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 32.0 + 22 * (names.take(4).length - 1),
                      height: 32,
                      child: Stack(
                        children: [
                          for (final (i, name) in names.take(4).indexed)
                            Positioned(
                              left: 22.0 * i,
                              child: ClassmateAvatar(
                                name,
                                me: i == 0,
                                size: 32,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: NiuSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${names.length} 人一起比對',
                            style: theme.textTheme.titleMedium,
                          ),
                          Text(
                            names.join('、'),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: NiuSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '顏色越深越多人有空，點格子看誰有空。',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () async {
                        final picked = await pickClassmates(
                          context,
                          widget.store,
                          term,
                          ids,
                        );
                        if (picked != null && picked.isNotEmpty && mounted) {
                          setState(() => ids = picked);
                        }
                      },
                      icon: const Icon(Icons.manage_accounts_rounded),
                      label: const Text('調整人選'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: NiuSpacing.xl),
          GroupAvailabilityView(group: group),
        ],
      );
    },
  );
}

class _FreeTimeList extends StatelessWidget {
  const _FreeTimeList({required this.lines});
  final List<String> lines;
  @override
  Widget build(BuildContext context) => NiuSection(
    title: '都沒課的時間',
    child: lines.isEmpty
        ? const NiuCard(
            child: NiuEmpty(
              icon: Icons.event_busy_rounded,
              title: '這學期沒有共同空堂',
              message: '試著少選幾位同學。',
            ),
          )
        : NiuGroup(
            insetDividers: NiuSpacing.lg,
            children: [
              for (final line in lines)
                NiuRow(
                  leading: Icon(
                    Icons.check_circle_rounded,
                    color: NiuHue.green.foreground(context),
                  ),
                  title: line,
                ),
            ],
          ),
  );
}

/// Sample classmates for the review account, lined up with its periods.
Future<void> addDemoClassmates(
  ScheduleExchangeStore store,
  String account,
  ClassSchedule school,
) async {
  final term = ScheduleShareTerm.containing(DateTime.now());
  const samples = [
    ('小安（示範）', ['經濟學', '英文閱讀', '程式設計']),
    ('阿哲（示範）', ['微積分', '體育', '普通物理']),
  ];
  for (final (n, (name, courses)) in samples.indexed) {
    final rows = school.periods.where(
      (p) => ScheduleSharePayload.periodSpan(p.time) != null,
    );
    final sample = ClassSchedule(scheduleWeekdays.take(5).toList(), [
      for (final (row, period) in rows.indexed)
        SchedulePeriod(period.label, period.time, {
          for (var day = 0; day < 5; day++)
            if ((row + day + n) % 3 == 0 && row < 8)
              scheduleWeekdays[day]: courses[(row + day) % courses.length],
        }),
    ]);
    final payload = ScheduleSharePayload.fromSchedule(
      sample,
      shareId: '00000000-0000-4000-8000-00000000000${n + 1}',
      term: term,
      nickname: name,
      createdAt: DateTime.now(),
    );
    await store.save(account, payload, replacing: store.existing(payload)?.id);
  }
}
