import 'package:flutter/material.dart';

import '../../core/session/campus_session.dart';
import '../../shared/shared.dart';
import 'postal_models.dart';
import 'postal_service.dart';
import 'postal_demo.dart';

/// Campus mail and parcel lookup. One search covers every status (the school
/// form takes one at a time); the status chips then filter locally. Like iOS,
/// it opens on the student's own mail, searched by their profile name.
class PostalScreen extends StatefulWidget {
  const PostalScreen({super.key, this.session, this.service});
  final CampusSession? session;
  final PostalService Function()? service;
  @override
  State<PostalScreen> createState() => _PostalScreenState();
}

class _PostalScreenState extends State<PostalScreen> {
  late final session = widget.session ?? CampusSession.instance;
  final name = TextEditingController();
  final phone = TextEditingController();
  final tracking = TextEditingController();

  /// Null shows every status.
  PostalStatus? filter;
  final clients = <PostalStatus, PostalService>{};
  final pages = <PostalStatus, PostalPage>{};
  bool loading = false, more = false;
  String? error;
  int generation = 0;

  /// Criteria of the results on screen, to flag edits made since.
  PostalQuery? searched;

  PostalQuery query(PostalStatus status) => PostalQuery(
    name: name.text,
    phone: phone.text,
    trackingNumber: tracking.text,
    status: status,
  ).normalized;

  bool get canSearch => query(PostalStatus.waiting).canSearch;

  bool get stale {
    final last = searched, now = query(PostalStatus.waiting);
    return last != null &&
        (last.name != now.name ||
            last.phone != now.phone ||
            last.trackingNumber != now.trackingNumber);
  }

  static const order = [
    PostalStatus.waiting,
    PostalStatus.returned,
    PostalStatus.collected,
  ];

  /// 未領取 first, then 退件, then 已領取; newest first within each.
  List<PostalRecord> get all {
    final list = [for (final status in order) ...?pages[status]?.records];
    list.sort((a, b) {
      final byStatus = order.indexOf(a.status) - order.indexOf(b.status);
      return byStatus != 0
          ? byStatus
          : b.receivedDate.compareTo(a.receivedDate);
    });
    return list;
  }

  List<PostalRecord> get records => [
    for (final r in all)
      if (filter == null || r.status == filter) r,
  ];

  int count(PostalStatus status) => pages[status]?.records.length ?? 0;

  bool get hasMore => pages.values.any((p) => p.nextForm != null);

  /// The student's name from the verified school profile, if any. A profile
  /// that only echoes the account is not a name.
  String get ownName {
    final name = session.profile['chName']?.toString().trim() ?? '';
    return name.toLowerCase() == session.account?.trim().toLowerCase()
        ? ''
        : name;
  }

  /// The name this screen filled in by itself, so a late or changed profile
  /// may replace it but never what the student typed.
  String? autoName;

  bool get untouched =>
      phone.text.trim().isEmpty &&
      tracking.text.trim().isEmpty &&
      (name.text.trim().isEmpty || name.text.trim() == autoName);

  @override
  void initState() {
    super.initState();
    session.addListener(_searchOwnMail);
    WidgetsBinding.instance.addPostFrameCallback((_) => _searchOwnMail());
  }

  void _searchOwnMail() {
    final own = ownName;
    if (!mounted || own.isEmpty || own == autoName || !untouched) return;
    if (autoName == null && (searched != null || loading)) return;
    autoName = name.text = own;
    search();
  }

  @override
  void dispose() {
    session.removeListener(_searchOwnMail);
    generation++;
    for (final c in clients.values) {
      c.close();
    }
    name.dispose();
    phone.dispose();
    tracking.dispose();
    super.dispose();
  }

  void _closeClients() {
    for (final c in clients.values) {
      c.close();
    }
    clients.clear();
  }

  Future<void> search() async {
    FocusScope.of(context).unfocus();
    if (!canSearch) return;
    final current = ++generation;
    final criteria = query(PostalStatus.waiting);
    _closeClients();
    setState(() {
      loading = true;
      error = null;
      pages.clear();
    });
    // One independent school session per status, queried in parallel.
    var failed = 0;
    String? message;
    await Future.wait([
      for (final status in PostalStatus.values)
        () async {
          final client = clients[status] =
              (widget.service ??
              (session.isDemo ? DemoPostalService.new : PostalService.new))();
          try {
            final page = await client.search(query(status));
            if (mounted && current == generation) pages[status] = page;
          } catch (e) {
            failed++;
            message = e is PostalException ? e.message : null;
          }
        }(),
    ]);
    if (!mounted || current != generation) return;
    setState(() {
      loading = false;
      searched = criteria;
      if (failed == PostalStatus.values.length) {
        error = message ?? '無法取得郵件資料，稍後再試一次。';
      } else if (failed > 0) {
        error = '部分狀態沒有查到，結果可能不完整。';
      }
    });
  }

  Future<void> loadMore() async {
    if (more) return;
    final current = generation;
    setState(() => more = true);
    try {
      await Future.wait([
        for (final entry in pages.entries.toList())
          if (entry.value.nextForm != null && clients[entry.key] != null)
            () async {
              final next = await clients[entry.key]!.nextPage(entry.value);
              if (!mounted || current != generation) return;
              final known = entry.value.records.map((r) => r.id).toSet();
              pages[entry.key] = PostalPage(
                records: [
                  ...entry.value.records,
                  ...next.records.where((r) => !known.contains(r.id)),
                ],
                query: next.query,
                pageIndex: next.pageIndex,
                pageCount: next.pageCount,
                nextForm: next.nextForm,
              );
            }(),
      ]);
    } catch (e) {
      if (mounted && current == generation) {
        setState(() => error = e is PostalException ? e.message : '無法載入更多結果');
      }
    } finally {
      if (mounted && current == generation) setState(() => more = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fillName =
        ownName.isNotEmpty && name.text.trim() != ownName && !loading;
    return NiuScrollPage(
      title: '郵件包裹',
      // Always set: toggling it rebuilds the page and collapses 更多條件.
      onRefresh: search,
      children: [
        NiuCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: name,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => search(),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: '收件人',
                  hintText: '輸入收件人姓名',
                  prefixIcon: const Icon(NiuIcons.person),
                  suffixIcon: fillName
                      ? Padding(
                          padding: const EdgeInsets.only(right: NiuSpacing.xs),
                          child: TextButton(
                            onPressed: () =>
                                setState(() => name.text = ownName),
                            child: const Text('帶入我的姓名'),
                          ),
                        )
                      : null,
                ),
              ),
              Theme(
                data: theme.copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  // Room for the floating label of the first field.
                  childrenPadding: const EdgeInsets.only(top: NiuSpacing.md),
                  title: Text('更多條件', style: theme.textTheme.titleSmall),
                  children: [
                    TextField(
                      controller: phone,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => search(),
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(labelText: '手機號碼'),
                    ),
                    const SizedBox(height: NiuSpacing.md),
                    TextField(
                      controller: tracking,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => search(),
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(labelText: '郵件號碼'),
                    ),
                    const SizedBox(height: NiuSpacing.md),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: loading || !canSearch ? null : search,
                icon: loading
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.search_rounded),
                label: Text(loading ? '查詢中' : '查詢'),
              ),
            ],
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: NiuSpacing.lg),
          NiuBanner(
            tone: NiuTone.warning,
            message: error!,
            actionLabel: canSearch && !loading ? '再試一次' : null,
            onAction: canSearch && !loading ? search : null,
          ),
        ],
        if (searched != null && !(loading && pages.isEmpty))
          NiuSection(
            title: '查詢結果',
            subtitle: stale
                ? '條件已變更，重新查詢以更新結果'
                : searched!.name == autoName &&
                      searched!.phone.isEmpty &&
                      searched!.trackingNumber.isEmpty
                ? '依登入姓名查詢'
                : null,
            action: Text(
              '${all.length} 筆',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFeatures: tabularFigures,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                NiuFilterBar<PostalStatus?>(
                  options: [
                    (null, '全部'),
                    for (final s in order) (s, '${s.label} ${count(s)}'),
                  ],
                  value: filter,
                  onChanged: (value) => setState(() => filter = value),
                ),
                const SizedBox(height: NiuSpacing.md),
                if (records.isEmpty)
                  NiuCard(
                    child: NiuEmpty(
                      padding: const EdgeInsets.symmetric(
                        vertical: NiuSpacing.xl,
                      ),
                      icon: Icons.inventory_2_outlined,
                      title: switch (filter) {
                        null => '沒有郵件紀錄',
                        PostalStatus.waiting => '沒有待領取的郵件',
                        PostalStatus.collected => '沒有已領取的紀錄',
                        PostalStatus.returned => '沒有退件紀錄',
                      },
                    ),
                  )
                else
                  for (final record in records)
                    Padding(
                      padding: const EdgeInsets.only(bottom: NiuSpacing.md),
                      child: _RecordCard(record: record),
                    ),
                if (hasMore)
                  OutlinedButton(
                    onPressed: more || loading ? null : loadMore,
                    child: Text(more ? '載入中' : '載入更多'),
                  ),
              ],
            ),
          )
        else if (loading)
          const NiuLoading(message: '正在查詢郵件'),
      ],
    );
  }
}

class _RecordCard extends StatelessWidget {
  const _RecordCard({required this.record});
  final PostalRecord record;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (tone, hue, icon) = switch (record.status) {
      PostalStatus.waiting => (
        NiuTone.accent,
        NiuHue.amber,
        Icons.inventory_2_outlined,
      ),
      PostalStatus.collected => (
        NiuTone.success,
        NiuHue.green,
        NiuIcons.success,
      ),
      PostalStatus.returned => (
        NiuTone.warning,
        NiuHue.orange,
        Icons.undo_rounded,
      ),
    };
    return NiuCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              NiuIconTile(icon: icon, hue: hue),
              const SizedBox(width: NiuSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      record.category.isEmpty ? '郵件' : record.category,
                      style: theme.textTheme.titleMedium,
                    ),
                    Text(
                      '收件日期 ${record.receivedDate}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFeatures: tabularFigures,
                      ),
                    ),
                  ],
                ),
              ),
              NiuBadge(label: record.status.label, tone: tone),
            ],
          ),
          const SizedBox(height: NiuSpacing.md),
          if (record.trackingNumber.isNotEmpty)
            NiuKeyValue(label: '郵件號碼', value: record.trackingNumber),
          NiuKeyValue(label: '收件人', value: record.recipient),
          if (record.unit.isNotEmpty)
            NiuKeyValue(label: '收件單位', value: record.unit),
          if (record.quantity.isNotEmpty && record.quantity != '1')
            NiuKeyValue(label: '數量', value: record.quantity),
          if (record.signature.isNotEmpty)
            NiuKeyValue(label: '簽收資訊', value: record.signature),
          if (record.completedDate.isNotEmpty)
            NiuKeyValue(
              label: record.status == PostalStatus.returned ? '退件日期' : '簽收日期',
              value: record.completedDate,
            ),
          if (record.note.isNotEmpty) ...[
            const SizedBox(height: NiuSpacing.xs),
            NiuWell(child: Text(record.note, style: theme.textTheme.bodySmall)),
          ],
        ],
      ),
    );
  }
}
