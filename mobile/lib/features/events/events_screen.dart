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
              : '尚未取得活動資料，請重新同步。';
        }
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => notices[tab] = snapshots.containsKey(tab)
              ? '同步失敗，仍顯示上次的活動資料。'
              : '無法取得活動資料，請稍後重試。',
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
    return Scaffold(
      appBar: IosPageHeader(
        title: '活動報名',
        actions: [
          CircleIconButton(
            label: '同步活動',
            icon: Icons.sync,
            onPressed: syncing ? null : sync,
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: CustomScrollView(
          key: PageStorageKey('events-$applied'),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AppSegmentedControl<bool>(
                      segments: const {
                        false: Text('可報名活動'),
                        true: Text('我的報名'),
                      },
                      segmentPadding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 12,
                      ),
                      value: applied,
                      onChanged: syncing
                          ? null
                          : (value) {
                              setState(() => applied = value);
                              if (!attempted.contains(value)) sync();
                            },
                    ),
                    const SizedBox(height: 16),
                    AppSearchField(
                      controller: queries[applied],
                      hint: '搜尋活動、主辦單位或地點',
                      onChanged: (_) => setState(() {}),
                    ),
                    if (notices[applied] case final notice?) ...[
                      const SizedBox(height: 12),
                      Text(
                        notice,
                        style: TextStyle(
                          color: NiuColors.of(context).secondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (events == null)
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverToBoxAdapter(
                  child: syncing
                      ? const AppLoadingState(message: '正在同步活動…')
                      : NiuEmptyState(
                          title: '尚未同步活動',
                          message: '連接校方活動系統，取得最新活動與報名紀錄。',
                          action: TextButton(
                            onPressed: sync,
                            child: const Text('同步活動'),
                          ),
                        ),
                ),
              ),
            if (filtered != null && filtered.isEmpty)
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverToBoxAdapter(
                  child: NiuEmptyState(
                    title: query.isNotEmpty
                        ? '找不到符合的活動'
                        : applied
                        ? '目前沒有報名紀錄'
                        : '目前沒有可顯示的活動',
                    message: query.isNotEmpty
                        ? '試試其他活動名稱、主辦單位或地點。'
                        : applied
                        ? '完成校方報名後，可在這裡同步查看。'
                        : '稍後可再次同步校方活動資料。',
                  ),
                ),
              ),
            if (filtered != null && filtered.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverList.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (_, index) => EventListCard(
                    event: filtered[index],
                    onTap: () => openDetail(filtered[index]),
                  ),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
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
      title: '同步活動',
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
              title: applied ? '修改／取消報名' : '報名活動',
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
            title: const Text('已完成報名變更？'),
            content: const Text('若已在校方頁面送出報名、修改或取消，返回列表時會同步最新紀錄。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('尚未變更'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('已完成變更'),
              ),
            ],
          ),
        );
    if (mounted && confirmed == true) setState(() => changed = true);
  }

  @override
  Widget build(BuildContext context) => PopScope<bool>(
    canPop: !changed,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) Navigator.of(context).pop(true);
    },
    child: Scaffold(
      appBar: const IosPageHeader(title: '活動詳情'),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            HeroCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.name.isEmpty ? '未提供活動名稱' : event.name,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 16),
                  EventStatusPill(status: event.status),
                ],
              ),
            ),
            const SectionHeader(title: '活動資訊'),
            EventFactGroup(
              facts: [
                ('活動時間', event.time),
                ('地點', event.location),
                ('主辦單位', event.department),
                ('認證時數', event.hours),
              ],
            ),
            const SectionHeader(title: '活動內容'),
            AppCard(
              child: SelectableText(
                event.details.trim().isEmpty ? '校方尚未提供活動內容。' : event.details,
              ),
            ),
            const SectionHeader(title: '報名資訊'),
            EventFactGroup(
              facts: [
                ('報名時間', event.registration),
                ('參加對象', event.targets),
                ('人數', event.people),
              ],
            ),
            if (event.contact.trim().isNotEmpty ||
                event.remark.trim().isNotEmpty) ...[
              const SectionHeader(title: '聯絡與備註'),
              EventFactGroup(
                facts: [
                  if (event.contact.trim().isNotEmpty) ('聯絡資訊', event.contact),
                  if (event.remark.trim().isNotEmpty) ('備註', event.remark),
                ],
              ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '報名與變更需在校方頁面送出，以校方結果為準。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: event.id.isEmpty || (!applied && !event.canApply)
                  ? null
                  : openAction,
              child: Text(applied ? '修改／取消報名' : '前往校方報名'),
            ),
          ],
        ),
      ),
    ),
  );
}
