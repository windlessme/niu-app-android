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
import 'space_booking_steps.dart';
import 'space_booking_bar.dart';
import 'space_reservation_card.dart';

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
      builder: (_) => SpaceConfirmSheet(
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
            ? SpaceBookingBar(
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
      SpaceStepCard(
        step: 1,
        title: '選擇日期',
        subtitle: dayTitle(c.date, today),
        accessory: TextButton.icon(
          onPressed: c.mutating ? null : _pickDate,
          icon: const Icon(NiuIcons.calendar, size: 18),
          label: const Text('其他日期'),
        ),
        child: SpaceDayStrip(
          today: today,
          selected: c.date,
          onSelect: c.mutating ? null : c.selectDate,
        ),
      ),
      const SizedBox(height: NiuSpacing.md),
      SpaceStepCard(
        step: 2,
        title: '選擇空間或設備',
        child: c.groups.isEmpty
            ? spacePlaceholder(
                context,
                c.loading ? '正在查詢設備…' : '目前沒有可供單日時段預約的設備。',
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (c.groups.length > 1) ...[
                    spaceCaption(theme, '類別'),
                    SpaceOptionGrid(
                      minWidth: 150,
                      children: [
                        for (final g in c.groups)
                          SpaceOption(
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
                  spaceCaption(theme, '設備'),
                  if (c.rooms.isEmpty)
                    spacePlaceholder(
                      context,
                      c.loading ? '正在查詢設備…' : '這個類別目前沒有可預約的設備。',
                    )
                  else
                    SpaceOptionGrid(
                      minWidth: 130,
                      children: [
                        for (final r in c.rooms)
                          SpaceOption(
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
      SpaceSlotSection(controller: c),
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
        spacePlaceholder(context, c.loading ? '正在取得預約紀錄…' : '尚未取得最新預約紀錄，請重新整理。')
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
          child: SpaceReservationCard(
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
