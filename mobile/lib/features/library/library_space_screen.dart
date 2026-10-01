import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/session/campus_session.dart';
import '../../core/time/campus_date.dart';
import '../../shared/shared.dart';
import '../authentication/remember_school_login.dart';
import '../demo/demo_services.dart';
import 'library_space_session.dart';
import 'space_models.dart';

/// 空間預約: the library's study rooms, discussion rooms and Switch, booked
/// through the library catalogue with the school account.
class LibrarySpaceScreen extends StatefulWidget {
  const LibrarySpaceScreen({super.key, this.session, this.service, this.now});
  final CampusSession? session;

  /// Skips sign-in; for tests.
  final SpaceService? service;
  final DateTime Function()? now;
  @override
  State<LibrarySpaceScreen> createState() => _LibrarySpaceScreenState();
}

enum _Phase { connecting, signIn, ready, failed }

class _LibrarySpaceScreenState extends State<LibrarySpaceScreen> {
  late final session = widget.session ?? CampusSession.instance;
  final password = TextEditingController();
  _Phase phase = _Phase.connecting;
  SpaceService? service;
  List<SpaceGroup> groups = const [];
  SpaceGroup? group;
  late CampusDate date = today;
  SpaceDay? day;
  List<SpaceReservation> mine = const [];
  bool loadingDay = false, signingIn = false;
  String? error, dayError;
  int generation = 0;

  DateTime get now => widget.now?.call() ?? DateTime.now();
  CampusDate get today => CampusDate.at(now);

  /// Taipei minute of day, so today's past slots are not offered.
  Minute get nowMinute {
    final t = now.toUtc().add(const Duration(hours: 8));
    return t.hour * 60 + t.minute;
  }

  List<CampusDate> get dates {
    final start = DateTime.utc(today.year, today.month, today.day);
    return [
      for (var i = 0; i < 7; i++)
        CampusDate.at(start.add(Duration(days: i, hours: -8))),
    ];
  }

  @override
  void initState() {
    super.initState();
    session.registerCleanup(_clear);
    connect();
  }

  @override
  void dispose() {
    generation++;
    session.unregisterCleanup(_clear);
    service?.close();
    password.dispose();
    super.dispose();
  }

  Future<void> _clear() async {
    generation++;
    service?.close();
    service = null;
    if (mounted) setState(() => phase = _Phase.signIn);
  }

  Future<void> connect() async {
    final current = ++generation;
    setState(() {
      phase = _Phase.connecting;
      error = null;
    });
    try {
      SpaceService? next =
          widget.service ??
          (session.isDemo
              ? DemoSpaceService(now: widget.now)
              : await LibrarySpaceSession(session).restore());
      if (next == null) {
        // A remembered school login signs the library in without asking.
        final saved = await RememberSchoolLogin.forSession(session).restore();
        if (saved != null && saved.account == session.account) {
          try {
            next = await LibrarySpaceSession(
              session,
            ).establish(saved.account, saved.password);
          } catch (_) {}
        }
      }
      if (!mounted || current != generation) {
        next?.close();
        return;
      }
      if (next == null) {
        setState(() => phase = _Phase.signIn);
        return;
      }
      service = next;
      await load();
    } catch (e) {
      if (!mounted || current != generation) return;
      setState(() {
        phase = _Phase.failed;
        error = e is SpaceException ? e.message : '無法連線到圖書館系統，請檢查網路後再試。';
      });
    }
  }

  Future<void> signIn() async {
    final account = session.account;
    if (account == null || password.text.isEmpty || signingIn) return;
    FocusScope.of(context).unfocus();
    final current = ++generation;
    setState(() {
      signingIn = true;
      error = null;
    });
    try {
      final next = await LibrarySpaceSession(
        session,
      ).establish(account, password.text);
      if (!mounted || current != generation) {
        next.close();
        return;
      }
      password.clear();
      service = next;
      await load();
    } catch (e) {
      if (!mounted || current != generation) return;
      setState(
        () => error = e is SpaceException ? e.message : '圖書館登入失敗，請確認網路後再試。',
      );
    } finally {
      if (mounted && current == generation) setState(() => signingIn = false);
    }
  }

  /// Groups, my reservations and the selected day.
  Future<void> load() async {
    final current = generation;
    final api = service;
    if (api == null) return;
    try {
      final results = await Future.wait([api.groups(), api.mine()]);
      if (!mounted || current != generation) return;
      final list = results[0] as List<SpaceGroup>;
      setState(() {
        groups = list;
        group =
            list.where((g) => g.id == group?.id).firstOrNull ??
            list.firstOrNull;
        mine = results[1] as List<SpaceReservation>;
        phase = _Phase.ready;
        error = null;
      });
      await loadDay();
    } catch (e) {
      if (!mounted || current != generation) return;
      setState(() {
        phase = _Phase.failed;
        error = e is SpaceException ? e.message : '無法取得圖書館資料，請稍後再試。';
      });
    }
  }

  Future<void> loadDay() async {
    final current = generation;
    final api = service, selected = group, on = date;
    if (api == null || selected == null) return;
    setState(() {
      loadingDay = true;
      dayError = null;
    });
    try {
      final next = await api.day(selected, on);
      if (!mounted || current != generation) return;
      if (selected != group || on != date) return;
      setState(() => day = next);
    } catch (e) {
      if (!mounted || current != generation) return;
      setState(() {
        day = null;
        dayError = e is SpaceException ? e.message : '無法取得這天的預約狀況';
      });
    } finally {
      if (mounted && current == generation) setState(() => loadingDay = false);
    }
  }

  Future<void> refresh() async {
    if (phase != _Phase.ready) return connect();
    final api = service;
    if (api == null) return;
    try {
      final list = await api.mine();
      if (mounted) setState(() => mine = list);
    } catch (_) {}
    await loadDay();
  }

  Future<void> book(SpaceRoom room, Minute start, Minute end) async {
    final api = service, selected = group, current = day;
    if (api == null || selected == null || current == null) return;
    try {
      await api.reserve(selected, room, current.date, start, end);
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '已預約 ${room.name} ${formatMinute(start)}–${formatMinute(end)}',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('預約沒有成功'),
          content: Text(e is SpaceException ? e.message : '請檢查網路後再試一次。'),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('確定'),
            ),
          ],
        ),
      );
    }
    await refresh();
  }

  Future<void> cancel(SpaceReservation reservation) async {
    final api = service;
    if (api == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('取消預約？'),
        content: Text(
          '${reservation.roomName}\n${_dateLabel(reservation.date)} '
          '${formatMinute(reservation.start)}–${formatMinute(reservation.end)}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('保留'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('取消預約'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await api.cancel(reservation);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已取消預約')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e is SpaceException ? e.message : '取消沒有成功，請再試一次。'),
        ),
      );
    }
    await refresh();
  }

  String _dateLabel(CampusDate d) {
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    final weekday = DateTime.utc(d.year, d.month, d.day).weekday;
    final prefix = d == today
        ? '今天 '
        : d == dates[1]
        ? '明天 '
        : '';
    return '$prefix${d.month}/${d.day}（${weekdays[weekday - 1]}）';
  }

  @override
  Widget build(BuildContext context) => NiuScrollPage(
    title: '空間預約',
    onRefresh: refresh,
    children: switch (phase) {
      _Phase.connecting => [const NiuLoading(message: '正在連線圖書館')],
      _Phase.signIn => [_signIn(context)],
      _Phase.failed => [
        NiuError(
          title: '無法使用空間預約',
          message: error ?? '請稍後再試。',
          onRetry: connect,
        ),
      ],
      _Phase.ready => _ready(context),
    },
  );

  Widget _signIn(BuildContext context) {
    final theme = Theme.of(context);
    return NiuCard(
      padding: const EdgeInsets.all(NiuSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(
            child: NiuIconTile(icon: NiuIcons.lock, hue: NiuHue.indigo),
          ),
          const SizedBox(height: NiuSpacing.md),
          Text(
            '登入圖書館',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: NiuSpacing.xs),
          Text(
            '圖書館使用校務系統的帳號密碼，輸入一次後會保持登入。',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: NiuSpacing.xl),
          NiuKeyValue(label: '帳號', value: session.account ?? ''),
          const SizedBox(height: NiuSpacing.md),
          TextField(
            controller: password,
            obscureText: true,
            autofillHints: const [AutofillHints.password],
            textInputAction: TextInputAction.go,
            onSubmitted: (_) => signIn(),
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: '密碼',
              prefixIcon: Icon(NiuIcons.lock),
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: NiuSpacing.md),
            NiuBanner(tone: NiuTone.error, message: error!),
          ],
          const SizedBox(height: NiuSpacing.lg),
          FilledButton(
            onPressed: signingIn || password.text.isEmpty ? null : signIn,
            child: Text(signingIn ? '登入中' : '登入'),
          ),
        ],
      ),
    );
  }

  List<Widget> _ready(BuildContext context) {
    final theme = Theme.of(context);
    final current = day;
    return [
      if (mine.isNotEmpty)
        NiuSection(
          title: '我的預約',
          first: true,
          child: Column(
            children: [
              for (final r in mine)
                Padding(
                  padding: const EdgeInsets.only(bottom: NiuSpacing.md),
                  child: _ReservationCard(
                    reservation: r,
                    dateLabel: _dateLabel(r.date),
                    onCancel: r.state == ReservationState.reserved
                        ? () => cancel(r)
                        : null,
                  ),
                ),
            ],
          ),
        ),
      NiuSection(
        title: '預約空間',
        first: mine.isEmpty,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            NiuFilterBar<SpaceGroup?>(
              options: [for (final g in groups) (g, g.name)],
              value: group,
              onChanged: (value) {
                if (value == null || value == group) return;
                setState(() {
                  group = value;
                  day = null;
                });
                loadDay();
              },
            ),
            const SizedBox(height: NiuSpacing.sm),
            NiuFilterBar<CampusDate>(
              options: [for (final d in dates) (d, _dateLabel(d))],
              value: date,
              onChanged: (value) {
                if (value == date) return;
                setState(() {
                  date = value;
                  day = null;
                });
                loadDay();
              },
            ),
            const SizedBox(height: NiuSpacing.md),
            if (dayError != null)
              NiuBanner(
                tone: NiuTone.warning,
                message: dayError!,
                actionLabel: loadingDay ? null : '再試一次',
                onAction: loadingDay ? null : loadDay,
              )
            else if (current == null)
              const NiuLoading(message: '正在查詢空位', compact: true)
            else ...[
              Text(
                '開放 ${formatMinute(current.rules.open)}–${formatMinute(current.rules.close)}'
                ' · 每次 ${_hours(current.rules.minHours)}–${_hours(current.rules.maxHours)} 小時',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFeatures: tabularFigures,
                ),
              ),
              const SizedBox(height: NiuSpacing.sm),
              const _Legend(),
              const SizedBox(height: NiuSpacing.md),
              for (final room in current.rooms)
                Padding(
                  padding: const EdgeInsets.only(bottom: NiuSpacing.md),
                  child: _RoomCard(
                    day: current,
                    room: room,
                    earliest: current.date == today
                        ? _ceilHalfHour(nowMinute)
                        : 0,
                    onPick: (start, end) => _pick(current, room, start, end),
                  ),
                ),
            ],
          ],
        ),
      ),
    ];
  }

  static Minute _ceilHalfHour(Minute m) => (m + 29) ~/ 30 * 30;

  static String _hours(double h) =>
      h == h.roundToDouble() ? '${h.round()}' : '$h';

  Future<void> _pick(
    SpaceDay day,
    SpaceRoom room,
    Minute from,
    Minute to,
  ) async {
    final picked = await showModalBottomSheet<(Minute, Minute)>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _BookingSheet(
        title: room.name,
        dateLabel: _dateLabel(day.date),
        from: from,
        to: to,
        rules: day.rules,
      ),
    );
    if (picked != null && mounted) await book(room, picked.$1, picked.$2);
  }
}

Color _booked(NiuColors colors) => colors.inkTertiary.withValues(alpha: 0.4);

class _Legend extends StatelessWidget {
  const _Legend();
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = NiuColors.of(context);
    Widget item(Color color, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: NiuSpacing.xs),
        Text(label, style: theme.textTheme.labelSmall),
      ],
    );
    return ExcludeSemantics(
      child: Wrap(
        spacing: NiuSpacing.md,
        runSpacing: NiuSpacing.xs,
        children: [
          item(colors.success.withValues(alpha: 0.55), '可預約'),
          item(_booked(colors), '已被預約'),
          item(colors.accent, '我預約的'),
          item(colors.fill, '已過時段'),
        ],
      ),
    );
  }
}

class _ReservationCard extends StatelessWidget {
  const _ReservationCard({
    required this.reservation,
    required this.dateLabel,
    this.onCancel,
  });
  final SpaceReservation reservation;
  final String dateLabel;
  final VoidCallback? onCancel;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = reservation;
    final inUse = r.state == ReservationState.inUse;
    final sameDay = r.endDate == r.date;
    return NiuCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const NiuIconTile(
                icon: Icons.meeting_room_outlined,
                hue: NiuHue.indigo,
              ),
              const SizedBox(width: NiuSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.roomName, style: theme.textTheme.titleMedium),
                    Text(
                      sameDay
                          ? '$dateLabel ${formatMinute(r.start)}–${formatMinute(r.end)}'
                          : '$dateLabel ${formatMinute(r.start)} 起至 '
                                '${r.endDate.month}/${r.endDate.day} ${formatMinute(r.end)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFeatures: tabularFigures,
                      ),
                    ),
                  ],
                ),
              ),
              NiuBadge(
                label: inUse ? '使用中' : '已預約',
                tone: inUse ? NiuTone.success : NiuTone.accent,
              ),
            ],
          ),
          if (!inUse && r.keepUntil != null) ...[
            const SizedBox(height: NiuSpacing.md),
            NiuWell(
              child: Text(
                '請在 ${formatMinute(r.keepUntil!)} 前到櫃台報到，逾時會取消預約。',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
          if (onCancel != null) ...[
            const SizedBox(height: NiuSpacing.md),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: onCancel, child: const Text('取消預約')),
            ),
          ],
        ],
      ),
    );
  }
}

/// One room's day: an availability bar and the free stretches to book.
class _RoomCard extends StatelessWidget {
  const _RoomCard({
    required this.day,
    required this.room,
    required this.earliest,
    required this.onPick,
  });
  final SpaceDay day;
  final SpaceRoom room;
  final Minute earliest;
  final void Function(Minute from, Minute to) onPick;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = NiuColors.of(context);
    final rules = day.rules;
    final free = freeIntervals(day, room.id, earliest: earliest);
    final span = (rules.close - rules.open).clamp(1, 24 * 60);
    final mine = day.of(room.id).where((b) => b.mine).toList();
    return NiuCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(room.name, style: theme.textTheme.titleMedium),
              ),
              if (mine.isNotEmpty)
                const NiuBadge(label: '已預約', tone: NiuTone.accent)
              else if (free.isEmpty)
                const NiuBadge(label: '已滿', tone: NiuTone.neutral),
            ],
          ),
          const SizedBox(height: NiuSpacing.md),
          Semantics(
            label: free.isEmpty
                ? '${room.name} 沒有空檔'
                : '${room.name} 空檔 ${free.map((f) => '${formatMinute(f.$1)} 到 ${formatMinute(f.$2)}').join('、')}',
            child: ExcludeSemantics(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(NiuRadius.xs),
                child: SizedBox(
                  height: 12,
                  child: LayoutBuilder(
                    builder: (context, box) {
                      double x(Minute m) =>
                          ((m - rules.open).clamp(0, span) / span) *
                          box.maxWidth;
                      return Stack(
                        children: [
                          Positioned.fill(
                            child: ColoredBox(color: _booked(colors)),
                          ),
                          if (earliest > rules.open)
                            Positioned(
                              left: 0,
                              width: x(earliest),
                              top: 0,
                              bottom: 0,
                              child: ColoredBox(color: colors.fill),
                            ),
                          for (final f in free)
                            Positioned(
                              left: x(f.$1),
                              width: x(f.$2) - x(f.$1),
                              top: 0,
                              bottom: 0,
                              child: ColoredBox(
                                color: colors.success.withValues(alpha: 0.55),
                              ),
                            ),
                          for (final b in mine)
                            Positioned(
                              left: x(b.start),
                              width: x(b.end) - x(b.start),
                              top: 0,
                              bottom: 0,
                              child: ColoredBox(color: colors.accent),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: NiuSpacing.xs),
          ExcludeSemantics(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final m in [
                  rules.open,
                  (rules.open + rules.close) ~/ 60 * 30,
                  rules.close,
                ])
                  Text(
                    formatMinute(m),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.inkTertiary,
                      fontFeatures: tabularFigures,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: NiuSpacing.md),
          if (free.isEmpty)
            Text('這天沒有可預約的空檔', style: theme.textTheme.bodySmall)
          else
            Wrap(
              spacing: NiuSpacing.sm,
              runSpacing: NiuSpacing.sm,
              children: [
                for (final f in free)
                  ActionChip(
                    avatar: const Icon(NiuIcons.add, size: 18),
                    label: Text(
                      '${formatMinute(f.$1)}–${formatMinute(f.$2)}',
                      style: const TextStyle(fontFeatures: tabularFigures),
                    ),
                    tooltip: '預約 ${room.name}',
                    onPressed: () => onPick(f.$1, f.$2),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Start and length within one free stretch, in half-hour steps.
class _BookingSheet extends StatefulWidget {
  const _BookingSheet({
    required this.title,
    required this.dateLabel,
    required this.from,
    required this.to,
    required this.rules,
  });
  final String title, dateLabel;
  final Minute from, to;
  final SpaceRules rules;
  @override
  State<_BookingSheet> createState() => _BookingSheetState();
}

class _BookingSheetState extends State<_BookingSheet> {
  late Minute start = widget.from;
  late int length = widget.rules.minMinutes;

  List<Minute> get starts => [
    for (var m = widget.from; m + widget.rules.minMinutes <= widget.to; m += 30)
      m,
  ];

  List<int> get lengths => [
    for (
      var l = widget.rules.minMinutes;
      l <= widget.rules.maxMinutes && start + l <= widget.to;
      l += 30
    )
      l,
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final options = lengths;
    if (!options.contains(length)) length = options.first;
    final end = start + length;
    return SafeArea(
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
            Text(widget.title, style: theme.textTheme.titleLarge),
            Text(widget.dateLabel, style: theme.textTheme.bodySmall),
            const SizedBox(height: NiuSpacing.xl),
            Text('開始時間', style: theme.textTheme.titleSmall),
            const SizedBox(height: NiuSpacing.sm),
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final m in starts)
                    Padding(
                      padding: const EdgeInsets.only(right: NiuSpacing.sm),
                      child: ChoiceChip(
                        label: Text(
                          formatMinute(m),
                          style: const TextStyle(fontFeatures: tabularFigures),
                        ),
                        selected: m == start,
                        onSelected: (_) => setState(() => start = m),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: NiuSpacing.lg),
            Text('使用時間', style: theme.textTheme.titleSmall),
            const SizedBox(height: NiuSpacing.sm),
            Wrap(
              spacing: NiuSpacing.sm,
              runSpacing: NiuSpacing.sm,
              children: [
                for (final l in options)
                  ChoiceChip(
                    label: Text(
                      '${_LibrarySpaceScreenState._hours(l / 60)} 小時',
                    ),
                    selected: l == length,
                    onSelected: (_) => setState(() => length = l),
                  ),
              ],
            ),
            const SizedBox(height: NiuSpacing.xl),
            FilledButton(
              onPressed: () => Navigator.pop(context, (start, end)),
              child: Text('預約 ${formatMinute(start)}–${formatMinute(end)}'),
            ),
          ],
        ),
      ),
    );
  }
}
