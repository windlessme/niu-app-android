import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/analytics/app_analytics.dart';
import '../../core/session/campus_session.dart';
import '../../core/web/academic_portal_screen.dart';
import '../../shared/shared.dart';
import 'event_portal.dart';
import 'event_actions.dart';
import 'event_widgets.dart';
import 'event_models.dart';
import 'events_demo.dart';

const eventsExtractScript = r'''
(() => {
  if (document.querySelector('input[type="password"]')) return null;
  const container = document.querySelector('.col-md-11.col-md-offset-1.col-sm-10.col-xs-12.col-xs-offset-0');
  if (!container) return null;
  const clean = e => (e?.innerText || '').trim();
  const states = document.querySelectorAll('.row.bg-warning');
  return JSON.stringify(Array.from(container.querySelectorAll('.row.enr-list-sec'), (row, i) => {
    const table = row.querySelector('.table');
    const cell = n => clean(table?.querySelectorAll('tr')[n]?.querySelectorAll('td')[1]);
    const iconText = selector => clean(row.querySelector(selector)?.parentElement);
    const link = row.querySelector('a[href*="/Act/RegData/"],a[href*="/Act/Apply/"]')?.href || '';
    const serial = clean(row.querySelector('p')).match(/[：:]\s*([A-Za-z0-9-]+)/)?.[1]
      || link.match(/\/Act\/(?:RegData|Apply)\/(\d+)/)?.[1];
    return {id: serial || '', name: clean(row.querySelector('h3')),
      action: link, targets: iconText('.fa-id-badge'),
      department: (row.querySelector('.enr-list-dep-nam')?.title || '').replace(/^.*?[：:]/, '').trim(),
      status: clean(states[i]?.querySelector('.text-danger.text-shadow')) || clean(row.querySelector('.badge.alert-danger')) || clean(row.querySelector('.btn.btn-danger')),
      time: iconText('.fa-calendar'), location: iconText('.fa-map-marker'),
      people: iconText('.fa-user-plus'), details: cell(3), contact: cell(5),
      remark: cell(7), hours: cell(8), registration: cell(9)};
  }));
})()
''';

typedef EventLoaderBuilder =
    Widget Function(BuildContext context, bool applied);
typedef EventActionBuilder =
    Widget Function(BuildContext context, CampusEvent event, bool applied);

class EventsScreen extends StatefulWidget {
  const EventsScreen({
    super.key,
    this.loaderBuilder,
    this.actionBuilder,
    this.actions,
  });
  final EventLoaderBuilder? loaderBuilder;

  /// School-page fallback for register / modify / cancel.
  final EventActionBuilder? actionBuilder;

  /// Native register / modify / cancel; defaults to the hidden school page.
  final EventActions? actions;
  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
  bool applied = false;
  bool syncing = false;
  final snapshots = <bool, List<CampusEvent>>{};
  final attempted = <bool>{};
  final notices = <bool, String>{};
  late final EventActions actions =
      widget.actions ??
      (CampusSession.instance.isDemo ? DemoEventActions() : WebEventActions());
  bool refreshingApplied = false;

  /// Keeps 「我的報名」 current in the background so 可報名活動 can hide
  /// events the student already joined.
  Future<void> refreshApplied() async {
    if (refreshingApplied) return;
    refreshingApplied = true;
    try {
      final result = await actions.registrations();
      if (mounted) setState(() => snapshots[true] = result);
    } catch (_) {
      // The 我的報名 tab can still sync explicitly.
    } finally {
      refreshingApplied = false;
    }
  }

  bool registered(CampusEvent event) {
    final mine = snapshots[true];
    if (mine == null) return false;
    return mine.any(
      (e) =>
          (e.id.isNotEmpty && e.id == event.id) ||
          (e.name.trim().isNotEmpty && e.name.trim() == event.name.trim()),
    );
  }

  /// Selected 多元認證 category per tab; null shows every event.
  final credits = <bool, String?>{};

  final queries = {
    false: TextEditingController(),
    true: TextEditingController(),
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) sync();
    });
  }

  @override
  void dispose() {
    for (final query in queries.values) {
      query.dispose();
    }
    super.dispose();
  }

  Future<void> sync() async {
    if (syncing) return;
    final tab = applied;
    setState(() {
      syncing = true;
      attempted.add(tab);
    });
    try {
      final result = await Navigator.of(context).push<List<CampusEvent>>(
        MaterialPageRoute(
          builder: (context) =>
              widget.loaderBuilder?.call(context, tab) ??
              EventSyncScreen(applied: tab),
        ),
      );
      if (!mounted) return;
      setState(() {
        if (result != null) {
          snapshots[tab] = result;
          notices.remove(tab);
          if (!tab && !attempted.contains(true)) unawaited(refreshApplied());
        } else {
          notices[tab] = snapshots.containsKey(tab)
              ? '同步未完成，仍顯示上次的活動資料。'
              : '還沒有取得活動資料，請再同步一次。';
        }
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => notices[tab] = snapshots.containsKey(tab)
              ? '同步失敗，仍顯示上次的活動資料。'
              : '無法取得活動資料，稍後再試一次。',
        );
      }
    } finally {
      if (mounted) setState(() => syncing = false);
    }
  }

  Future<void> openDetail(CampusEvent event) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EventDetailScreen(
          event: event,
          applied: applied,
          actionBuilder: widget.actionBuilder,
          actions: actions,
        ),
      ),
    );
    if (mounted && changed == true) {
      // A registration change affects both lists: refresh the visible tab
      // and, in the background, 「我的報名」.
      if (!applied) unawaited(refreshApplied());
      await sync();
    }
  }

  @override
  Widget build(BuildContext context) {
    final events = snapshots[applied];
    final query = queries[applied]!.text.trim().toLowerCase();
    final visible = events
        ?.where((event) => applied || !registered(event))
        .toList();
    // Categories in the order the school lists them.
    final categories = <String>{
      for (final event in visible ?? const <CampusEvent>[])
        for (final credit in event.credits)
          if (credit.category.isNotEmpty) credit.category,
    }.toList();
    final credit = categories.contains(credits[applied])
        ? credits[applied]
        : null;
    final filtered = visible
        ?.where((event) => event.matches(query))
        .where(
          (event) =>
              credit == null || event.credits.any((c) => c.category == credit),
        )
        .toList();
    return NiuScrollPage(
      key: PageStorageKey('events-$applied'),
      title: '活動報名',
      actions: [
        NiuIconButton(
          tooltip: '同步活動',
          icon: NiuIcons.refresh,
          onPressed: syncing ? null : sync,
        ),
      ],
      children: [
        NiuSegmented<bool>(
          segments: const [(false, '可報名活動'), (true, '我的報名')],
          value: applied,
          onChanged: syncing
              ? null
              : (value) {
                  setState(() => applied = value);
                  if (!attempted.contains(value)) sync();
                },
        ),
        const SizedBox(height: NiuSpacing.md),
        NiuSearchField(
          controller: queries[applied],
          hint: '搜尋活動名稱、編號、主辦單位或地點',
          onChanged: (_) => setState(() {}),
        ),
        if (categories.isNotEmpty) ...[
          const SizedBox(height: NiuSpacing.md),
          NiuFilterBar<String?>(
            options: [
              (null, '全部認證'),
              for (final category in categories) (category, category),
            ],
            value: credit,
            onChanged: (value) => setState(() => credits[applied] = value),
          ),
        ],
        if (notices[applied] case final notice?) ...[
          const SizedBox(height: NiuSpacing.md),
          NiuBanner(tone: NiuTone.warning, message: notice),
        ],
        const SizedBox(height: NiuSpacing.lg),
        if (filtered != null && filtered.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: NiuSpacing.sm),
            child: Text(
              query.isEmpty && credit == null
                  ? '${filtered.length} 個活動'
                  : '找到 ${filtered.length} 個活動',
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
        if (events == null)
          syncing
              ? const NiuLoading(message: '正在同步活動')
              : NiuEmpty(
                  icon: NiuIcons.events,
                  tone: NiuTone.accent,
                  title: '尚未同步活動',
                  message: '連上學校的活動系統，取得最新活動與你的報名紀錄。',
                  action: FilledButton.tonal(
                    onPressed: sync,
                    child: const Text('同步活動'),
                  ),
                ),
        if (filtered != null && filtered.isEmpty)
          NiuEmpty(
            icon: query.isNotEmpty || credit != null
                ? NiuIcons.search
                : NiuIcons.events,
            title: query.isNotEmpty || credit != null
                ? '找不到符合的活動'
                : applied
                ? '目前沒有報名紀錄'
                : '目前沒有開放的活動',
            message: credit != null && query.isEmpty
                ? '目前沒有「$credit」的活動。'
                : query.isNotEmpty
                ? '換個活動名稱、編號、主辦單位或地點試試。'
                : applied
                ? '在學校網頁報名後，同步一下就會出現。'
                : '稍後再同步看看。',
          ),
        if (filtered != null)
          for (final event in filtered)
            Padding(
              padding: const EdgeInsets.only(bottom: NiuSpacing.md),
              child: EventListCard(
                event: event,
                onTap: () => openDetail(event),
              ),
            ),
      ],
    );
  }
}

/// The school portal owns authentication and extraction. A successful snapshot
/// returns to the native list; failure/back leaves the previous snapshot intact.
class EventSyncScreen extends StatelessWidget {
  const EventSyncScreen({super.key, required this.applied});
  final bool applied;
  @override
  Widget build(BuildContext context) {
    final target = Uri.parse(
      'https://ccsys.niu.edu.tw/MvcTeam/Act${applied ? '/ApplyMe' : ''}',
    );
    return AcademicPortalScreen(
      title: '活動報名',
      target: target,
      bridge: false,
      entryBuilder: (session) => eventPortalEntry(session, target: target),
      navigationScript: eventNavigationScript(target),
      extractScript: eventsExtractScript,
      demoSnapshot: () => DemoEvents.list(applied: applied),
      onSnapshot: (value, _) async {
        final events = (value as List)
            .map(
              (e) => CampusEvent.fromJson(Map<String, dynamic>.from(e as Map)),
            )
            .toList();
        if (context.mounted) Navigator.of(context).pop(events);
      },
    );
  }
}

class EventDetailScreen extends StatefulWidget {
  const EventDetailScreen({
    super.key,
    required this.event,
    this.applied = false,
    this.actionBuilder,
    this.actions,
  });
  final CampusEvent event;
  final bool applied;
  final EventActionBuilder? actionBuilder;
  final EventActions? actions;
  @override
  State<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends State<EventDetailScreen> {
  bool changed = false;
  bool busy = false;
  bool cancelled = false;
  String? busyText;
  EventActionResult? result;
  late final EventActions actions = widget.actions ?? WebEventActions();
  CampusEvent get event => widget.event;
  bool get applied => widget.applied;

  Future<void> perform(
    String progress,
    Future<EventActionResult> Function() action,
  ) async {
    if (busy) return;
    setState(() {
      busy = true;
      busyText = progress;
      result = null;
    });
    final outcome = await action();
    if (!mounted) return;
    setState(() {
      busy = false;
      result = outcome;
      if (outcome.success) changed = true;
    });
    outcome.success
        ? HapticFeedback.mediumImpact()
        : HapticFeedback.heavyImpact();
  }

  Future<void> register() async {
    final ok = await confirmNiuAction(
      context,
      title: '報名這個活動？',
      message: '「${event.name}」\n報名後可以在「我的報名」修改或取消。',
      confirmLabel: '報名',
    );
    if (!ok) return;
    await perform('正在報名', () => actions.register(event));
    AppAnalytics.instance.result('event_register', result?.success ?? false);
  }

  Future<void> cancelRegistration() async {
    final ok = await confirmNiuAction(
      context,
      title: '取消報名？',
      message: '「${event.name}」的報名會被取消，名額可能無法保留。',
      confirmLabel: '取消報名',
      destructive: true,
    );
    if (!ok) return;
    await perform('正在取消報名', () => actions.cancel(event));
    AppAnalytics.instance.result('event_cancel', result?.success ?? false);
    if (mounted && (result?.success ?? false)) setState(() => cancelled = true);
  }

  Future<void> edit() async {
    final saved = await Navigator.of(context).push<EventActionResult>(
      MaterialPageRoute(
        builder: (_) => EventRegistrationEditScreen(
          event: event,
          actions: actions,
          onOpenWeb: openAction,
        ),
      ),
    );
    if (saved != null) {
      AppAnalytics.instance.result('event_update', saved.success);
    }
    if (!mounted || saved == null) return;
    setState(() {
      result = saved;
      if (saved.success) changed = true;
    });
  }

  Future<void> openAction() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) =>
            widget.actionBuilder?.call(context, event, applied) ??
            AcademicPortalScreen(
              title: applied ? '修改或取消報名' : '報名',
              target: event.actionUri(applied: applied),
              bridge: false,
              entryBuilder: (session) => eventPortalEntry(
                session,
                target: event.actionUri(applied: applied),
              ),
              navigationScript: eventNavigationScript(
                event.actionUri(applied: applied),
              ),
            ),
      ),
    );
    if (!mounted) return;
    final confirmed =
        result ??
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('報名有變更嗎？'),
            content: const Text('如果已在學校網頁送出報名、修改或取消，返回列表時會同步最新紀錄。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('沒有變更'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('已送出變更'),
              ),
            ],
          ),
        );
    if (mounted && confirmed == true) setState(() => changed = true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope<bool>(
      canPop: !changed,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(true);
      },
      child: NiuScrollPage(
        title: '活動詳情',
        actions: [
          NiuIconButton(
            tooltip: '分享活動',
            icon: NiuIcons.share,
            onPressed: () =>
                SharePlus.instance.share(ShareParams(text: event.shareText)),
          ),
        ],
        bottomBar: _actionBar(context),
        children: [
          NiuCard(
            padding: const EdgeInsets.all(NiuSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const NiuIconTile(icon: NiuIcons.events, hue: NiuHue.green),
                const SizedBox(height: NiuSpacing.md),
                SelectableText(
                  event.name.isEmpty ? '-' : event.name,
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: NiuSpacing.md),
                Wrap(
                  spacing: NiuSpacing.sm,
                  runSpacing: NiuSpacing.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    EventStatusPill(status: event.status),
                    if (event.id.isNotEmpty) EventNumberChip(id: event.id),
                  ],
                ),
              ],
            ),
          ),
          if (result != null) ...[
            const SizedBox(height: NiuSpacing.lg),
            NiuBanner(
              tone: result!.success ? NiuTone.success : NiuTone.warning,
              title: result!.success ? '完成' : '沒有完成',
              message: result!.message,
              actionLabel: result!.needsWeb ? '在學校網頁操作' : null,
              onAction: result!.needsWeb ? openAction : null,
            ),
          ],
          NiuSection(
            title: '活動資訊',
            child: EventFactGroup(
              facts: [
                ('主辦單位', event.department),
                ('活動時間', event.time),
                ('活動地點', event.location),
                (
                  '多元認證',
                  event.credits.isEmpty
                      ? event.hours
                      : event.credits.map((c) => c.label).join('\n'),
                ),
              ],
            ),
          ),
          NiuSection(
            title: '活動內容',
            child: NiuCard(
              child: SelectableText(
                event.details.trim().isEmpty ? '-' : event.details,
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ),
          NiuSection(
            title: '報名資訊',
            child: EventFactGroup(
              facts: [
                ('報名時間', event.registration),
                ('參加對象', event.targets),
                ('報名人數', event.people),
              ],
            ),
          ),
          if (event.contact.trim().isNotEmpty || event.remark.trim().isNotEmpty)
            NiuSection(
              title: '聯絡與備註',
              child: EventFactGroup(
                facts: [
                  if (event.contact.trim().isNotEmpty) ('聯絡方式', event.contact),
                  if (event.remark.trim().isNotEmpty) ('備註', event.remark),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _actionBar(BuildContext context) {
    final theme = Theme.of(context);
    if (busy) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          const SizedBox(width: NiuSpacing.md),
          Text(busyText ?? '處理中', style: theme.textTheme.titleSmall),
        ],
      );
    }
    final unavailable = event.id.isEmpty || (!applied && !event.canApply);
    final registeredNow = !applied && (result?.success ?? false);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!applied)
          FilledButton(
            onPressed: unavailable || registeredNow ? null : register,
            child: Text(registeredNow ? '已報名' : '報名'),
          )
        else if (!cancelled)
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: NiuColors.of(context).error,
                  ),
                  onPressed: unavailable ? null : cancelRegistration,
                  child: const Text('取消報名'),
                ),
              ),
              const SizedBox(width: NiuSpacing.md),
              Expanded(
                child: FilledButton(
                  onPressed: unavailable ? null : edit,
                  child: const Text('修改資料'),
                ),
              ),
            ],
          ),
        const SizedBox(height: NiuSpacing.sm),
        Text(
          unavailable && !applied ? '這個活動目前不開放報名。' : '送出後以學校報名系統的紀錄為準。',
          textAlign: TextAlign.center,
          style: theme.textTheme.labelMedium,
        ),
      ],
    );
  }
}

/// Native form for the school's RegData page (contact, meal, certificate).
class EventRegistrationEditScreen extends StatefulWidget {
  const EventRegistrationEditScreen({
    super.key,
    required this.event,
    required this.actions,
    this.onOpenWeb,
  });
  final CampusEvent event;
  final EventActions actions;
  final VoidCallback? onOpenWeb;
  @override
  State<EventRegistrationEditScreen> createState() =>
      _EventRegistrationEditScreenState();
}

class _EventRegistrationEditScreenState
    extends State<EventRegistrationEditScreen> {
  late Future<EventRegistrationForm> future = widget.actions.loadForm(
    widget.event,
  );
  final tel = TextEditingController();
  final email = TextEditingController();
  final memo = TextEditingController();
  String? food, proof;
  bool filled = false, saving = false;
  EventActionResult? failure;

  @override
  void dispose() {
    tel.dispose();
    email.dispose();
    memo.dispose();
    super.dispose();
  }

  void fill(EventRegistrationForm form) {
    if (filled) return;
    filled = true;
    tel.text = form.tel;
    email.text = form.email;
    memo.text = form.memo;
    food = form.food.where((c) => c.checked).firstOrNull?.value;
    proof = form.proof.where((c) => c.checked).firstOrNull?.value;
  }

  Future<void> save() async {
    setState(() {
      saving = true;
      failure = null;
    });
    final result = await widget.actions.save(
      widget.event,
      tel: tel.text.trim(),
      email: email.text.trim(),
      memo: memo.text.trim(),
      food: food,
      proof: proof,
    );
    if (!mounted) return;
    if (result.success) {
      Navigator.of(context).pop(result);
      return;
    }
    setState(() {
      saving = false;
      failure = result;
    });
  }

  Widget choices(
    String title,
    List<EventChoice> options,
    String? value,
    ValueChanged<String> onChanged,
  ) => NiuSection(
    title: title,
    child: NiuGroup(
      insetDividers: NiuSpacing.lg,
      children: [
        for (final option in options)
          Semantics(
            selected: option.value == value,
            inMutuallyExclusiveGroup: true,
            child: NiuRow(
              title: option.label,
              chevron: false,
              onTap: saving
                  ? null
                  : () => setState(() => onChanged(option.value)),
              trailing: Icon(
                option.value == value
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: option.value == value
                    ? NiuColors.of(context).accent
                    : NiuColors.of(context).inkTertiary,
              ),
            ),
          ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => FutureBuilder<EventRegistrationForm>(
    future: future,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        final message = snapshot.error is EventFormUnavailable
            ? (snapshot.error as EventFormUnavailable).message
            : '無法讀取報名資料，請稍後再試。';
        return NiuScrollPage(
          title: '修改報名資料',
          children: [
            NiuError(
              title: '無法讀取報名資料',
              message: message,
              onRetry: () => setState(
                () => future = widget.actions.loadForm(widget.event),
              ),
              secondaryAction: widget.onOpenWeb == null
                  ? null
                  : TextButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        widget.onOpenWeb!();
                      },
                      child: const Text('在學校網頁操作'),
                    ),
            ),
          ],
        );
      }
      if (!snapshot.hasData) {
        return const NiuScrollPage(
          title: '修改報名資料',
          children: [NiuLoading(message: '正在讀取報名資料')],
        );
      }
      final form = snapshot.data!;
      fill(form);
      return NiuScrollPage(
        title: '修改報名資料',
        bottomBar: FilledButton(
          onPressed: saving ? null : save,
          child: Text(saving ? '正在儲存' : '儲存修改'),
        ),
        children: [
          Text(
            widget.event.name,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (failure != null) ...[
            const SizedBox(height: NiuSpacing.lg),
            NiuBanner(tone: NiuTone.warning, message: failure!.message),
          ],
          if (form.info.isNotEmpty)
            NiuSection(
              title: '基本資料',
              child: NiuCard(
                child: Column(
                  children: [
                    for (final (label, value) in form.info)
                      NiuKeyValue(label: label, value: value),
                  ],
                ),
              ),
            ),
          NiuSection(
            title: '聯絡資訊',
            child: NiuCard(
              child: Column(
                children: [
                  TextField(
                    controller: tel,
                    enabled: !saving,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: '電話'),
                  ),
                  const SizedBox(height: NiuSpacing.md),
                  TextField(
                    controller: email,
                    enabled: !saving,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: '信箱'),
                  ),
                ],
              ),
            ),
          ),
          if (form.food.isNotEmpty)
            choices('飲食', form.food, food, (v) => food = v),
          if (form.proof.isNotEmpty)
            choices('活動認證', form.proof, proof, (v) => proof = v),
          NiuSection(
            title: '備註',
            child: NiuCard(
              child: TextField(
                controller: memo,
                enabled: !saving,
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(hintText: '選填'),
              ),
            ),
          ),
        ],
      );
    },
  );
}
