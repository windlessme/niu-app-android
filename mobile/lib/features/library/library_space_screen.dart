import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/session/campus_session.dart';
import '../../core/time/campus_date.dart';
import '../../shared/shared.dart';
import '../authentication/remember_school_login.dart';
import 'space_demo.dart';
import 'library_space_session.dart';
import 'space_booking_controller.dart';
import 'space_models.dart';

/// 設備預約: the library's study rooms, discussion rooms and Switch. Same flow
/// as the iOS app — pick a day, a room, a start slot, then the length.
class LibrarySpaceScreen extends StatefulWidget {
  const LibrarySpaceScreen({super.key, this.session, this.service, this.now});
  final CampusSession? session;

  /// Skips sign-in; for tests.
  final SpaceService? service;
  final DateTime Function()? now;
  @override
  State<LibrarySpaceScreen> createState() => _LibrarySpaceScreenState();
}

class _LibrarySpaceScreenState extends State<LibrarySpaceScreen> {
  late final session = widget.session ?? CampusSession.instance;
  late final controller = SpaceBookingController(
    now: widget.now ?? DateTime.now,
    restore: _restore,
    signInWith: (password) =>
        LibrarySpaceSession(session).establish(session.account ?? '', password),
  );
  final password = TextEditingController();
  final search = TextEditingController();
  bool showReservations = false;
  ReservationPeriod period = ReservationPeriod.all;
  int? filterRoom;

  Future<SpaceService?> _restore() async {
    if (widget.service != null) return widget.service;
    if (session.isDemo) return DemoSpaceService();
    final restored = await LibrarySpaceSession(session).restore();
    if (restored != null) return restored;
    // A remembered school login signs the library in without asking.
    final saved = await RememberSchoolLogin.forSession(session).restore();
    if (saved == null || saved.account != session.account) return null;
    try {
      return await LibrarySpaceSession(
        session,
      ).establish(saved.account, saved.password);
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    session.registerCleanup(_clear);
    controller.connect();
  }

  @override
  void dispose() {
    session.unregisterCleanup(_clear);
    controller.dispose();
    password.dispose();
    search.dispose();
    super.dispose();
  }

  Future<void> _clear() async => controller.signedOut();

  CampusDate get today => controller.today;

  Future<void> _review() async {
    final draft = await controller.prepare();
    if (draft == null || !mounted) return;
    final result = await showModalBottomSheet<SpaceCompletion>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ConfirmSheet(
        controller: controller,
        draft: draft,
        dateLabel: _fullDate(draft.date),
      ),
    );
    if (result != null && mounted) await _announce(result);
  }

  Future<void> _cancel(SpaceReservation r) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('取消這筆預約？'),
        content: Text(
          '${r.roomName}\n${_fullDate(r.date)} '
          '${formatMinute(r.start)}–${formatMinute(r.end)}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('保留預約'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: NiuColors.of(context).error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('取消預約'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final result = await controller.cancel(r);
    if (result != null && mounted) await _announce(result);
  }

  Future<void> _announce(SpaceCompletion result) async {
    HapticFeedback.mediumImpact();
    final show = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(result.title),
        content: Text(result.message),
        actions: [
          if (result.reserved)
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('查看我的預約'),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
    if (show == true && mounted) setState(() => showReservations = true);
  }

  Future<void> _pickDate() async {
    final first = DateTime(today.year, today.month, today.day);
    final current = controller.date;
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(current.year, current.month, current.day),
      firstDate: first,
      lastDate: first.add(const Duration(days: 90)),
      helpText: '選擇預約日期',
    );
    if (picked != null) {
      controller.selectDate(CampusDate(picked.year, picked.month, picked.day));
    }
  }

  String _fullDate(CampusDate d) => '${webpacDate(d)}（${shortWeekday(d)}）';

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final c = controller;
      final ready = c.phase == SpacePhase.ready;
      return NiuScrollPage(
        title: '設備預約',
        actions: [
          if (ready)
            NiuIconButton(
              icon: NiuIcons.refresh,
              tooltip: '重新整理設備與我的預約',
              onPressed: c.busy ? null : c.refresh,
            ),
        ],
        onRefresh: ready ? c.refresh : c.connect,
        bottomBar: ready && !showReservations
            ? _BookingBar(
                controller: c,
                dayLabel: dayTitle(c.date, today),
                onReview: _review,
                onVerify: () => setState(() => showReservations = true),
              )
            : null,
        children: switch (c.phase) {
          SpacePhase.connecting => [const NiuLoading(message: '正在連線圖書館')],
          SpacePhase.signIn => [_signIn(context)],
          SpacePhase.failed => [
            NiuError(
              title: '無法使用設備預約',
              message: c.error ?? '請稍後再試。',
              onRetry: c.connect,
            ),
          ],
          SpacePhase.ready => _ready(context),
        },
      );
    },
  );

  Widget _signIn(BuildContext context) {
    final theme = Theme.of(context);
    final c = controller;
    return NiuCard(
      padding: const EdgeInsets.all(NiuSpacing.xl),
      child: AutofillGroup(
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
              onSubmitted: (_) => _submitPassword(),
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: '密碼',
                prefixIcon: Icon(NiuIcons.lock),
              ),
            ),
            if (c.signInError != null) ...[
              const SizedBox(height: NiuSpacing.md),
              NiuBanner(tone: NiuTone.error, message: c.signInError!),
            ],
            const SizedBox(height: NiuSpacing.lg),
            FilledButton(
              onPressed: c.signingIn || password.text.isEmpty
                  ? null
                  : _submitPassword,
              child: Text(c.signingIn ? '登入中' : '登入'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submitPassword() async {
    FocusScope.of(context).unfocus();
    await controller.signIn(password.text);
    if (controller.phase == SpacePhase.ready) password.clear();
  }

  List<Widget> _ready(BuildContext context) {
    final theme = Theme.of(context);
    final colors = NiuColors.of(context);
    final c = controller;
    final count = c.reservations.length;
    final stamp = showReservations ? c.reservationsUpdatedAt : c.updatedAt;
    return [
      NiuSegmented<bool>(
        segments: [
          (false, '預約設備'),
          (true, count == 0 ? '我的預約' : '我的預約（$count）'),
        ],
        value: showReservations,
        onChanged: (value) => setState(() => showReservations = value),
      ),
      const SizedBox(height: NiuSpacing.sm),
      // Fixed height: only the words change while updating.
      SizedBox(
        height: 20,
        child: Row(
          children: [
            if (c.busy)
              const SizedBox.square(
                dimension: 12,
                child: CircularProgressIndicator(strokeWidth: 1.5),
              )
            else
              Icon(NiuIcons.time, size: 14, color: colors.inkTertiary),
            const SizedBox(width: NiuSpacing.xs),
            Text(
              c.mutating
                  ? '正在送交圖書館…'
                  : c.loading
                  ? '正在更新…'
                  : stamp == null
                  ? '尚未更新'
                  : '最後更新 ${_stamp(stamp)}',
              style: theme.textTheme.labelMedium?.copyWith(
                fontFeatures: tabularFigures,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: NiuSpacing.md),
      ..._banners(),
      if (showReservations) ..._reservations(context) else ..._booking(context),
      const SizedBox(height: NiuSpacing.xl),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => openPublicUrl(
            context,
            Uri.parse('https://webpacx.niu.edu.tw/equipment'),
          ),
          icon: const Icon(NiuIcons.external, size: 18),
          label: const Text('開啟圖書館設備預約網站'),
        ),
      ),
      Text('這裡提供單日時段預約；全日、多日或週期預約請使用圖書館網站。', style: theme.textTheme.bodySmall),
    ];
  }

  String _stamp(DateTime t) {
    final d = t.toUtc().add(const Duration(hours: 8));
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.month)}/${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  List<Widget> _banners() {
    final c = controller;
    return [
      if (c.needsVerification)
        _gap(
          NiuBanner(
            tone: NiuTone.warning,
            message: c.notice ?? const SpaceUncertain().message,
            actionLabel: showReservations ? null : '查看我的預約',
            onAction: showReservations
                ? null
                : () => setState(() => showReservations = true),
          ),
        )
      else if (c.notice != null)
        _gap(NiuBanner(tone: NiuTone.success, message: c.notice!)),
      if (c.error != null)
        _gap(
          NiuBanner(
            tone: NiuTone.error,
            message: c.error!,
            actionLabel: c.busy ? null : '重新整理',
            onAction: c.busy ? null : c.refresh,
          ),
        ),
    ];
  }

  Widget _gap(Widget child) => Padding(
    padding: const EdgeInsets.only(bottom: NiuSpacing.md),
    child: child,
  );

  // ── 預約設備 ──────────────────────────────────────────────────────────────

  List<Widget> _booking(BuildContext context) {
    final c = controller;
    final theme = Theme.of(context);
    return [
      _StepCard(
        step: 1,
        title: '選擇日期',
        subtitle: dayTitle(c.date, today),
        accessory: TextButton.icon(
          onPressed: c.mutating ? null : _pickDate,
          icon: const Icon(NiuIcons.calendar, size: 18),
          label: const Text('其他日期'),
        ),
        child: _DayStrip(
          today: today,
          selected: c.date,
          onSelect: c.mutating ? null : c.selectDate,
        ),
      ),
      const SizedBox(height: NiuSpacing.md),
      _StepCard(
        step: 2,
        title: '選擇空間或設備',
        child: c.groups.isEmpty
            ? _placeholder(context, c.loading ? '正在查詢設備…' : '目前沒有可供單日時段預約的設備。')
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (c.groups.length > 1) ...[
                    _caption(theme, '類別'),
                    _OptionGrid(
                      minWidth: 150,
                      children: [
                        for (final g in c.groups)
                          _Option(
                            title: g.name,
                            detail: g.total > 0 ? '共 ${g.total} 項' : null,
                            selected: g.id == c.groupId,
                            onTap: c.mutating
                                ? null
                                : () => c.selectGroup(g.id),
                          ),
                      ],
                    ),
                    const SizedBox(height: NiuSpacing.md),
                  ],
                  _caption(theme, '設備'),
                  if (c.rooms.isEmpty)
                    _placeholder(
                      context,
                      c.loading ? '正在查詢設備…' : '這個類別目前沒有可預約的設備。',
                    )
                  else
                    _OptionGrid(
                      minWidth: 130,
                      children: [
                        for (final r in c.rooms)
                          _Option(
                            title: r.name,
                            selected: r.id == c.roomId,
                            onTap: c.mutating ? null : () => c.selectRoom(r.id),
                          ),
                      ],
                    ),
                ],
              ),
      ),
      const SizedBox(height: NiuSpacing.md),
      _SlotSection(controller: c),
    ];
  }

  // ── 我的預約 ──────────────────────────────────────────────────────────────

  List<Widget> _reservations(BuildContext context) {
    final c = controller;
    final theme = Theme.of(context);
    final rooms = <int, String>{
      for (final r in c.reservations) r.roomId: r.roomName,
    };
    if (filterRoom != null && !rooms.containsKey(filterRoom)) filterRoom = null;
    final filtered = filterReservations(
      c.reservations,
      today: today,
      query: search.text,
      period: period,
      roomId: filterRoom,
    );
    final filtering =
        search.text.trim().isNotEmpty ||
        period != ReservationPeriod.all ||
        filterRoom != null;
    return [
      NiuSearchField(
        controller: search,
        hint: '搜尋設備名稱、日期或時間',
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: NiuSpacing.sm),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final p in ReservationPeriod.values)
              Padding(
                padding: const EdgeInsets.only(right: NiuSpacing.sm),
                child: NiuFilterChip(
                  label: p.label,
                  selected: period == p,
                  onSelected: (_) => setState(() => period = p),
                ),
              ),
            if (rooms.length > 1 || filterRoom != null)
              PopupMenuButton<int?>(
                tooltip: '依設備篩選',
                initialValue: filterRoom,
                onSelected: (value) => setState(() => filterRoom = value),
                itemBuilder: (_) => [
                  const PopupMenuItem(value: null, child: Text('全部設備')),
                  for (final e in rooms.entries)
                    PopupMenuItem(value: e.key, child: Text(e.value)),
                ],
                child: IgnorePointer(
                  child: NiuFilterChip(
                    label: '${rooms[filterRoom] ?? '全部設備'} ▾',
                    selected: filterRoom != null,
                    onSelected: (_) {},
                  ),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: NiuSpacing.xs),
      Row(
        children: [
          Expanded(
            child: Text(
              '顯示 ${filtered.length} / ${c.reservations.length} 筆',
              style: theme.textTheme.bodySmall?.copyWith(
                fontFeatures: tabularFigures,
              ),
            ),
          ),
          if (filtering)
            TextButton(
              onPressed: () => setState(() {
                search.clear();
                period = ReservationPeriod.all;
                filterRoom = null;
              }),
              child: const Text('清除條件'),
            ),
        ],
      ),
      const SizedBox(height: NiuSpacing.sm),
      if (c.reservationsUpdatedAt == null && c.reservations.isEmpty)
        _placeholder(context, c.loading ? '正在取得預約紀錄…' : '尚未取得最新預約紀錄，請重新整理。')
      else if (c.reservations.isEmpty)
        const NiuCard(
          child: NiuEmpty(
            icon: NiuIcons.calendar,
            title: '目前沒有預約',
            message: '完成預約後，會在這裡顯示設備與時段。',
          ),
        )
      else if (filtered.isEmpty)
        const NiuCard(
          child: NiuEmpty(
            icon: NiuIcons.search,
            title: '沒有符合條件的預約',
            message: '試試其他設備名稱、日期，或清除篩選條件。',
          ),
        ),
      for (final r in filtered)
        Padding(
          padding: const EdgeInsets.only(bottom: NiuSpacing.md),
          child: _ReservationCard(
            reservation: r,
            today: today,
            onCancel:
                r.state == ReservationState.reserved &&
                    !c.busy &&
                    !c.needsVerification
                ? () => _cancel(r)
                : null,
          ),
        ),
      if (c.needsVerification && c.reservationsUpdatedAt != null)
        FilledButton(
          onPressed: c.busy ? null : c.acknowledgeVerification,
          child: const Text('我已核對最新紀錄'),
        ),
    ];
  }
}

Widget _caption(ThemeData theme, String text) => Padding(
  padding: const EdgeInsets.only(bottom: NiuSpacing.sm),
  child: Semantics(
    header: true,
    child: Text(text, style: theme.textTheme.labelMedium),
  ),
);

Widget _placeholder(BuildContext context, String text) => ConstrainedBox(
  constraints: const BoxConstraints(minHeight: 44),
  child: Align(
    alignment: Alignment.centerLeft,
    child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
  ),
);

/// A numbered step; the accessory sits beside the heading when it fits.
class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.step,
    required this.title,
    required this.child,
    this.subtitle,
    this.accessory,
  });
  final int step;
  final String title;
  final String? subtitle;
  final Widget? accessory;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = NiuColors.of(context);
    final heading = Semantics(
      header: true,
      label: ['步驟 $step', title, ?subtitle].join('，'),
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            margin: const EdgeInsets.only(top: 1),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.accent,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$step',
              style: theme.textTheme.labelMedium?.copyWith(
                color: colors.onAccent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: NiuSpacing.sm),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFeatures: tabularFigures,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    return NiuCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (accessory == null)
            heading
          else
            Row(
              children: [
                Expanded(
                  child: Align(alignment: Alignment.centerLeft, child: heading),
                ),
                accessory!,
              ],
            ),
          const SizedBox(height: NiuSpacing.md),
          child,
        ],
      ),
    );
  }
}

/// Two weeks of day buttons; further dates come from 其他日期.
class _DayStrip extends StatefulWidget {
  const _DayStrip({
    required this.today,
    required this.selected,
    required this.onSelect,
  });
  final CampusDate today, selected;
  final ValueChanged<CampusDate>? onSelect;
  @override
  State<_DayStrip> createState() => _DayStripState();
}

class _DayStripState extends State<_DayStrip> {
  static const _count = 14, _width = 58.0, _gap = NiuSpacing.sm;
  final scroll = ScrollController();

  @override
  void didUpdateWidget(covariant _DayStrip old) {
    super.didUpdateWidget(old);
    if (old.selected != widget.selected) _reveal();
  }

  void _reveal() {
    final index = daysBetween(widget.today, widget.selected);
    if (index < 0 || index >= _count || !scroll.hasClients) return;
    final target =
        index * (_width + _gap) -
        (scroll.position.viewportDimension - _width) / 2;
    scroll.animateTo(
      target.clamp(0, scroll.position.maxScrollExtent),
      duration: NiuMotion.duration(context),
      curve: NiuMotion.curve,
    );
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = NiuColors.of(context);
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6);
    return SizedBox(
      height: 74 * scale,
      child: ListView.separated(
        controller: scroll,
        scrollDirection: Axis.horizontal,
        itemCount: _count,
        separatorBuilder: (_, _) => const SizedBox(width: _gap),
        itemBuilder: (context, i) {
          final day = addDays(widget.today, i);
          final selected = day == widget.selected;
          final relative = relativeDay(day, widget.today);
          final ink = selected
              ? colors.onAccent
              : i == 0
              ? colors.accent
              : colors.ink;
          return Semantics(
            selected: selected,
            button: true,
            label:
                '${relative == null ? '' : '$relative，'}'
                '${day.month}月${day.day}日，${shortWeekday(day)}',
            excludeSemantics: true,
            child: Material(
              color: selected ? colors.accent : colors.fill,
              borderRadius: BorderRadius.circular(NiuRadius.md),
              child: InkWell(
                borderRadius: BorderRadius.circular(NiuRadius.md),
                onTap: widget.onSelect == null
                    ? null
                    : () => widget.onSelect!(day),
                child: SizedBox(
                  width: _width * scale.clamp(1.0, 1.4),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        relative ?? shortWeekday(day),
                        style: theme.textTheme.labelSmall?.copyWith(color: ink),
                      ),
                      Text(
                        '${day.day}',
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: ink,
                          fontWeight: FontWeight.w700,
                          fontFeatures: tabularFigures,
                          height: 1.15,
                        ),
                      ),
                      Text(
                        '${day.month}月',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: ink.withValues(alpha: 0.8),
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
    );
  }
}

/// Equal-width options laid out in as many columns as fit.
class _OptionGrid extends StatelessWidget {
  const _OptionGrid({required this.minWidth, required this.children});
  final double minWidth;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);
      final columns = (box.maxWidth / (minWidth * scale)).floor().clamp(1, 6);
      final width = (box.maxWidth - NiuSpacing.sm * (columns - 1)) / columns;
      return Wrap(
        spacing: NiuSpacing.sm,
        runSpacing: NiuSpacing.sm,
        children: [
          for (final child in children) SizedBox(width: width, child: child),
        ],
      );
    },
  );
}

/// Selection shown by tick, outline and colour together.
class _Option extends StatelessWidget {
  const _Option({
    required this.title,
    required this.selected,
    required this.onTap,
    this.detail,
  });
  final String title;
  final String? detail;
  final bool selected;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = NiuColors.of(context);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(NiuRadius.md),
      side: BorderSide(
        color: selected ? colors.accent : Colors.transparent,
        width: 1.5,
      ),
    );
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? colors.accentSoft : colors.fill,
        shape: shape,
        child: InkWell(
          customBorder: shape,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: NiuSpacing.md,
                vertical: NiuSpacing.sm,
              ),
              child: Row(
                children: [
                  if (selected) ...[
                    Icon(Icons.check_rounded, size: 18, color: colors.accent),
                    const SizedBox(width: NiuSpacing.xs),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: selected ? colors.accent : colors.ink,
                          ),
                        ),
                        if (detail != null)
                          Text(detail!, style: theme.textTheme.labelSmall),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Step 3: start time ───────────────────────────────────────────────────────

class _SlotSection extends StatelessWidget {
  const _SlotSection({required this.controller});
  final SpaceBookingController controller;

  static const _periods = [
    ('上午', 0, 12 * 60),
    ('下午', 12 * 60, 18 * 60),
    ('晚上', 18 * 60, 24 * 60),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = controller;
    final rules = c.rules;
    return _StepCard(
      step: 3,
      title: '選擇開始時間',
      subtitle: rules == null
          ? null
          : '開放 ${formatMinute(rules.open)}–${formatMinute(rules.close)} · 每格 30 分鐘',
      child: rules == null
          ? _placeholder(
              context,
              c.loading
                  ? '正在取得可預約時段…'
                  : c.selectionMessage ?? '選好設備後，這裡會顯示當日時段。',
            )
          : _content(context, theme, rules),
    );
  }

  Widget _content(BuildContext context, ThemeData theme, SpaceRules rules) {
    final c = controller;
    final all = c.slots;
    final upcoming = [
      for (final s in all)
        if (s.state != SlotState.past) s,
    ];
    final past = [
      for (final s in all)
        if (s.state == SlotState.past) s,
    ];
    final label = c.timeLabel;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (rules.quotaExhausted) ...[
          const NiuBanner(tone: NiuTone.warning, message: '剩餘額度不足以建立新的預約。'),
          const SizedBox(height: NiuSpacing.md),
        ],
        if (upcoming.isEmpty)
          Text('這天已沒有尚未開始的時段，請選擇其他日期。', style: theme.textTheme.bodyMedium)
        else ...[
          Text(
            label != null
                ? '已選 $label，可拖曳下方滑桿調整時長；點其他時間可重新選擇。'
                : '點選開始時間，最短預約 ${formatHours(rules.minHours)} 小時。',
            style: theme.textTheme.bodySmall,
          ),
          for (final (name, from, to) in _periods)
            if (upcoming.any((s) => s.minute >= from && s.minute < to)) ...[
              const SizedBox(height: NiuSpacing.md),
              _caption(theme, name),
              _SlotGrid(
                slots: [
                  for (final s in upcoming)
                    if (s.minute >= from && s.minute < to) s,
                ],
                controller: c,
              ),
            ],
        ],
        if (past.isNotEmpty)
          Theme(
            data: theme.copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(
                '已開始的時段（${past.length}）',
                style: theme.textTheme.titleSmall,
              ),
              expandedAlignment: Alignment.centerLeft,
              childrenPadding: const EdgeInsets.only(bottom: NiuSpacing.sm),
              children: [
                Text(
                  past.map((s) => formatMinute(s.minute)).join('、'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFeatures: tabularFigures,
                  ),
                ),
              ],
            ),
          )
        else
          const SizedBox(height: NiuSpacing.md),
        Row(
          children: [
            Expanded(
              child: _Stat(
                label: '剩餘額度',
                value: '${formatHours(rules.remainingHours)} 小時',
              ),
            ),
            const SizedBox(width: NiuSpacing.sm),
            Expanded(
              child: _Stat(
                label: '單次可預約',
                value:
                    '${formatHours(rules.minHours)}–${formatHours(rules.maxHours)} 小時',
              ),
            ),
          ],
        ),
        Theme(
          data: theme.copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text('使用規則', style: theme.textTheme.titleSmall),
            expandedAlignment: Alignment.centerLeft,
            childrenPadding: EdgeInsets.zero,
            children: [
              Text(
                '每次 ${formatHours(rules.minHours)}–${formatHours(rules.maxHours)} 小時，'
                '以 30 分鐘調整。預約需連續且不得跨過已占用的時段，並依圖書館規定報到。',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MergeSemantics(
      child: NiuWell(
        padding: const EdgeInsets.all(NiuSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.labelSmall),
            const SizedBox(height: 2),
            Text(
              value,
              style: theme.textTheme.titleSmall?.copyWith(
                fontFeatures: tabularFigures,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SlotGrid extends StatelessWidget {
  const _SlotGrid({required this.slots, required this.controller});
  final List<SpaceSlot> slots;
  final SpaceBookingController controller;
  @override
  Widget build(BuildContext context) => _OptionGrid(
    minWidth: 72,
    children: [
      for (final s in slots)
        _SlotCell(
          slot: s,
          start: controller.start == s.minute && controller.timeLabel != null,
          selected: controller.isSelected(s.minute),
          onTap: controller.busy
              ? null
              : () => controller.selectStart(s.minute),
        ),
    ],
  );
}

/// One 30-minute cell: filled when free, outlined with a reason when not.
class _SlotCell extends StatelessWidget {
  const _SlotCell({
    required this.slot,
    required this.start,
    required this.selected,
    required this.onTap,
  });
  final SpaceSlot slot;
  final bool start, selected;
  final VoidCallback? onTap;

  String get status {
    if (selected) return start ? '開始' : '已選';
    return switch (slot.state) {
      SlotState.available => '可選',
      SlotState.occupied => '已占用',
      SlotState.mine => '我的預約',
      SlotState.past => '已開始',
      SlotState.tooShort => '空檔不足',
      SlotState.quota => '額度不足',
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = NiuColors.of(context);
    final available = slot.state == SlotState.available;
    final enabled = available || selected;
    final (Color fill, Color ink, Color border) = start
        ? (colors.accent, colors.onAccent, Colors.transparent)
        : selected
        ? (
            colors.accentSoft,
            colors.accent,
            colors.accent.withValues(alpha: 0.5),
          )
        : slot.state == SlotState.mine
        ? (
            Colors.transparent,
            colors.accent,
            colors.accent.withValues(alpha: 0.5),
          )
        : available
        ? (colors.fill, colors.ink, Colors.transparent)
        : (Colors.transparent, colors.inkTertiary, colors.hairline);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(NiuRadius.sm),
      side: BorderSide(color: border),
    );
    final time = formatMinute(slot.minute);
    final spoken = slot.state == SlotState.tooShort && !selected
        ? '空檔 ${formatHours(slot.continuous / 60)} 小時，不足最短預約時長'
        : status;
    return Semantics(
      button: enabled,
      selected: selected,
      label: '$time，$spoken',
      excludeSemantics: true,
      child: Material(
        color: fill,
        shape: shape,
        child: InkWell(
          customBorder: shape,
          onTap: enabled ? onTap : null,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: NiuSpacing.xs),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    time,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: ink,
                      fontFeatures: tabularFigures,
                      decoration: slot.state == SlotState.occupied && !selected
                          ? TextDecoration.lineThrough
                          : null,
                      decorationColor: ink,
                    ),
                  ),
                  Text(
                    status,
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                    style: theme.textTheme.labelSmall?.copyWith(color: ink),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Bottom bar ───────────────────────────────────────────────────────────────

/// Pinned summary of the choice, the length slider and the review button.
class _BookingBar extends StatelessWidget {
  const _BookingBar({
    required this.controller,
    required this.dayLabel,
    required this.onReview,
    required this.onVerify,
  });
  final SpaceBookingController controller;
  final String dayLabel;
  final VoidCallback onReview, onVerify;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = NiuColors.of(context);
    final c = controller;
    final label = c.timeLabel;
    final max = c.maxDuration;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MergeSemantics(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label ?? '尚未選擇時段',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontFeatures: tabularFigures,
                      ),
                    ),
                    Text(
                      '${c.room?.name ?? '請選擇設備'} · $dayLabel',
                      maxLines: 2,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (label != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: NiuSpacing.md,
                    vertical: NiuSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: colors.accentSoft,
                    borderRadius: BorderRadius.circular(NiuRadius.pill),
                  ),
                  child: Text(
                    '${formatHours(c.duration / 60)} 小時',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: colors.accent,
                      fontFeatures: tabularFigures,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (label != null && max != null && max > c.minDuration) ...[
          Slider(
            value: c.duration.toDouble(),
            min: c.minDuration.toDouble(),
            max: max.toDouble(),
            divisions: (max - c.minDuration) ~/ 30,
            label: '${formatHours(c.duration / 60)} 小時',
            semanticFormatterCallback: (v) => '${formatHours(v / 60)} 小時',
            onChanged: c.busy ? null : (v) => c.setDuration(v.round()),
          ),
          ExcludeSemantics(
            child: Row(
              children: [
                Text(
                  '${formatHours(c.minDuration / 60)} 小時',
                  style: theme.textTheme.labelSmall,
                ),
                const Spacer(),
                Text(
                  '最多 ${formatHours(max / 60)} 小時',
                  style: theme.textTheme.labelSmall,
                ),
              ],
            ),
          ),
        ] else if (label != null && max != null)
          Padding(
            padding: const EdgeInsets.only(top: NiuSpacing.xs),
            child: Text(
              '這個開始時間只能預約 ${formatHours(max / 60)} 小時。',
              style: theme.textTheme.bodySmall,
            ),
          )
        else if (c.start == null)
          Padding(
            padding: const EdgeInsets.only(top: NiuSpacing.xs),
            child: Text(
              '點選上方的開始時間，再拖曳滑桿調整時長。',
              style: theme.textTheme.bodySmall,
            ),
          ),
        if (c.selectionMessage != null)
          Padding(
            padding: const EdgeInsets.only(top: NiuSpacing.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(NiuIcons.info, size: 16, color: colors.inkSecondary),
                const SizedBox(width: NiuSpacing.xs),
                Expanded(
                  child: Text(
                    c.selectionMessage!,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: NiuSpacing.md),
        if (c.needsVerification)
          FilledButton(onPressed: onVerify, child: const Text('查看我的預約並核對'))
        else
          FilledButton.icon(
            onPressed: c.busy || c.selectionError != null ? null : onReview,
            iconAlignment: IconAlignment.end,
            icon: c.loading
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.arrow_forward_rounded),
            label: Text(c.loading ? '正在核對…' : '核對預約'),
          ),
      ],
    );
  }
}

// ── Confirmation ─────────────────────────────────────────────────────────────

class _ConfirmSheet extends StatefulWidget {
  const _ConfirmSheet({
    required this.controller,
    required this.draft,
    required this.dateLabel,
  });
  final SpaceBookingController controller;
  final SpaceDraft draft;
  final String dateLabel;
  @override
  State<_ConfirmSheet> createState() => _ConfirmSheetState();
}

class _ConfirmSheetState extends State<_ConfirmSheet> {
  bool sending = false;

  Future<void> send() async {
    setState(() => sending = true);
    final result = await widget.controller.submit(widget.draft);
    if (mounted) Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final d = widget.draft;
    return PopScope(
      canPop: !sending,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            NiuSpacing.gutter,
            0,
            NiuSpacing.gutter,
            NiuSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('確認設備預約', style: theme.textTheme.titleLarge),
              const SizedBox(height: NiuSpacing.lg),
              Row(
                children: [
                  const NiuIconTile(
                    icon: Icons.event_available_rounded,
                    hue: NiuHue.indigo,
                  ),
                  const SizedBox(width: NiuSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(d.room.name, style: theme.textTheme.titleMedium),
                        Text(d.group.name, style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: NiuSpacing.lg),
              NiuWell(
                child: Column(
                  children: [
                    NiuKeyValue(label: '日期', value: widget.dateLabel),
                    NiuKeyValue(label: '時段', value: d.timeLabel),
                    NiuKeyValue(
                      label: '時長',
                      value: '${formatHours(d.minutes / 60)} 小時',
                    ),
                    NiuKeyValue(
                      label: '目前剩餘額度',
                      value: '${formatHours(d.rules.remainingHours)} 小時',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: NiuSpacing.sm),
              Text(
                '送出時會再次核對時段與規則。預約完成後，請依圖書館規定報到。',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: NiuSpacing.xl),
              FilledButton(
                onPressed: sending ? null : send,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (sending) ...[
                      const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: NiuSpacing.sm),
                    ],
                    Text(sending ? '正在送出…' : '確認並送出預約'),
                  ],
                ),
              ),
              const SizedBox(height: NiuSpacing.sm),
              TextButton(
                onPressed: sending ? null : () => Navigator.pop(context),
                child: const Text('返回'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 我的預約 card ─────────────────────────────────────────────────────────────

class _ReservationCard extends StatelessWidget {
  const _ReservationCard({
    required this.reservation,
    required this.today,
    required this.onCancel,
  });
  final SpaceReservation reservation;
  final CampusDate today;
  final VoidCallback? onCancel;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = NiuColors.of(context);
    final r = reservation;
    final inUse = r.state == ReservationState.inUse;
    String two(int v) => v.toString().padLeft(2, '0');
    final endDay = r.endDate == r.date
        ? ''
        : '${two(r.endDate.month)}/${two(r.endDate.day)} ';
    final time = '${formatMinute(r.start)}–$endDay${formatMinute(r.end)}';
    final keep = r.keepUntil;
    final secondary = theme.textTheme.bodySmall?.copyWith(
      fontFeatures: tabularFigures,
    );
    return NiuCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(
                child: Container(
                  constraints: const BoxConstraints(
                    minWidth: 60,
                    minHeight: 60,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: NiuSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: colors.accentSoft,
                    borderRadius: BorderRadius.circular(NiuRadius.md),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        relativeDay(r.date, today) ?? shortWeekday(r.date),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.accent,
                        ),
                      ),
                      Text(
                        '${r.date.month}/${r.date.day}',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: colors.accent,
                          fontWeight: FontWeight.w700,
                          fontFeatures: tabularFigures,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: NiuSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            r.roomName,
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                        NiuBadge(
                          label: inUse ? '使用中' : '已預約',
                          tone: inUse ? NiuTone.accent : NiuTone.success,
                        ),
                      ],
                    ),
                    const SizedBox(height: NiuSpacing.xs),
                    _line(
                      NiuIcons.calendar,
                      '${webpacDate(r.date)}（${shortWeekday(r.date)}）',
                      secondary,
                      colors,
                    ),
                    _line(
                      NiuIcons.time,
                      '$time · ${formatHours(r.minutes / 60)} 小時',
                      secondary,
                      colors,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if ((keep != null && !inUse) ||
              r.state == ReservationState.reserved) ...[
            const SizedBox(height: NiuSpacing.md),
            Divider(height: 1, color: colors.hairline),
            const SizedBox(height: NiuSpacing.sm),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: NiuSpacing.sm,
              runSpacing: NiuSpacing.xs,
              children: [
                if (keep != null && !inUse)
                  _line(
                    Icons.hourglass_bottom_rounded,
                    '保留期限 ${webpacDate(keep.$1)} ${formatMinute(keep.$2)}',
                    secondary,
                    colors,
                  ),
                if (r.state == ReservationState.reserved)
                  Semantics(
                    label:
                        '取消 ${r.roomName}，${webpacDate(r.date)} ${formatMinute(r.start)} 的預約',
                    button: true,
                    excludeSemantics: true,
                    child: OutlinedButton(
                      onPressed: onCancel,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: colors.error,
                        side: BorderSide(
                          color: colors.error.withValues(alpha: 0.5),
                        ),
                      ),
                      child: const Text('取消預約'),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _line(
    IconData icon,
    String text,
    TextStyle? style,
    NiuColors colors,
  ) => Padding(
    padding: const EdgeInsets.only(top: 2),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: colors.inkTertiary),
        const SizedBox(width: NiuSpacing.xs),
        Flexible(child: Text(text, style: style)),
      ],
    ),
  );
}
