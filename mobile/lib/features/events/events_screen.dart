import 'package:flutter/material.dart';

import '../../core/web/academic_portal_screen.dart';
import '../../shared/shared.dart';
import 'event_portal.dart';
import 'event_widgets.dart';

class CampusEvent {
  CampusEvent.fromJson(Map<String, dynamic> json)
    : id = json['id']?.toString() ?? '',
      name = json['name']?.toString() ?? '',
      department = json['department']?.toString() ?? '',
      status = json['status']?.toString() ?? '',
      time = json['time']?.toString() ?? '',
      location = json['location']?.toString() ?? '',
      details = json['details']?.toString() ?? '',
      registration = json['registration']?.toString() ?? '',
      contact = json['contact']?.toString() ?? '',
      remark = json['remark']?.toString() ?? '',
      hours = json['hours']?.toString() ?? '',
      action = json['action']?.toString() ?? '',
      targets = json['targets']?.toString() ?? '',
      people = json['people']?.toString() ?? '';
  final String action, targets;
  bool get canApply =>
      id.isNotEmpty &&
      !status.contains('已結束') &&
      !status.contains('截止') &&
      (targets.isEmpty || targets.contains('本校在校生'));
  final String id,
      name,
      department,
      status,
      time,
      location,
      details,
      registration,
      contact,
      remark,
      hours,
      people;
  Uri actionUri({required bool applied}) {
    final link = Uri.tryParse(action);
    if (link != null &&
        link.scheme == 'https' &&
        link.host == 'ccsys.niu.edu.tw' &&
        link.userInfo.isEmpty &&
        link.port == 443 &&
        link.path.startsWith(
          applied ? '/MvcTeam/Act/RegData/' : '/MvcTeam/Act/Apply/',
        )) {
      return link;
    }
    return Uri.https(
      'ccsys.niu.edu.tw',
      '/MvcTeam/Act/${applied ? 'RegData' : 'Apply'}/$id',
    );
  }
}

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
    const serial = clean(row.querySelector('p')).match(/[：:]\s*(\S+)/);
    return {id: serial?.[1] || '', name: clean(row.querySelector('h3')),
      action: row.querySelector('a[href*="/Act/RegData/"],a[href*="/Act/Apply/"]')?.href || '', targets: iconText('.fa-id-badge'),
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
  const EventsScreen({super.key, this.loaderBuilder, this.actionBuilder});
  final EventLoaderBuilder? loaderBuilder;
  final EventActionBuilder? actionBuilder;
  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
  bool applied = false;
  bool syncing = false;
  final snapshots = <bool, List<CampusEvent>>{};
  final attempted = <bool>{};
  final notices = <bool, String>{};
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
        ),
      ),
    );
    if (mounted && changed == true) {
      // A registration change can affect both lists. Refresh the visible tab;
      // retain the other snapshot until its next explicit sync.
      await sync();
    }
  }

  @override
  Widget build(BuildContext context) {
    final events = snapshots[applied];
    final query = queries[applied]!.text.trim().toLowerCase();
    final filtered = events
        ?.where(
          (event) => [
            event.name,
            event.department,
            event.location,
          ].any((value) => value.toLowerCase().contains(query)),
        )
        .toList();
    return NiuScrollPage(
      key: PageStorageKey('events-$applied'),
      title: '活動報名',
      actions: [
        NiuIconButton(
          tooltip: '同步活動',
          icon: Icons.sync_rounded,
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
          hint: '搜尋活動、主辦單位或地點',
          onChanged: (_) => setState(() {}),
        ),
        if (notices[applied] case final notice?) ...[
          const SizedBox(height: NiuSpacing.md),
          NiuBanner(tone: NiuTone.warning, message: notice),
        ],
        const SizedBox(height: NiuSpacing.lg),
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
            icon: query.isNotEmpty ? NiuIcons.search : NiuIcons.events,
            title: query.isNotEmpty
                ? '找不到符合的活動'
                : applied
                ? '目前沒有報名紀錄'
                : '目前沒有開放的活動',
            message: query.isNotEmpty
                ? '換個活動名稱、主辦單位或地點試試。'
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
  });
  final CampusEvent event;
  final bool applied;
  final EventActionBuilder? actionBuilder;
  @override
  State<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends State<EventDetailScreen> {
  bool changed = false;
  CampusEvent get event => widget.event;
  bool get applied => widget.applied;

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
        bottomBar: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton(
              onPressed: event.id.isEmpty || (!applied && !event.canApply)
                  ? null
                  : openAction,
              child: Text(applied ? '修改或取消報名' : '前往報名'),
            ),
            const SizedBox(height: NiuSpacing.sm),
            Text(
              '報名與變更在學校網頁送出，結果以學校為準。',
              textAlign: TextAlign.center,
              style: theme.textTheme.labelMedium,
            ),
          ],
        ),
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
                EventStatusPill(status: event.status),
              ],
            ),
          ),
          NiuSection(
            title: '活動資訊',
            child: EventFactGroup(
              facts: [
                ('時間', event.time),
                ('地點', event.location),
                ('主辦單位', event.department),
                ('認證時數', event.hours),
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
                ('人數', event.people),
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
}
