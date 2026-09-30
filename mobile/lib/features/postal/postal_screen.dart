import 'package:flutter/material.dart';

import '../../core/session/campus_session.dart';
import '../../shared/shared.dart';
import 'postal_models.dart';
import 'postal_service.dart';

/// Campus mail and parcel lookup. Opens with the student's own name and
/// 未領取 already searched, so the common question is answered at once.
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

  /// Null searches every status at once (the school form takes only one).
  PostalStatus? filter;
  final clients = <PostalStatus, PostalService>{};
  final pages = <PostalStatus, PostalPage>{};
  bool searched = false, loading = false, more = false;
  String? error;
  int generation = 0;

  List<PostalStatus> get statuses =>
      filter == null ? PostalStatus.values : [filter!];

  PostalQuery query(PostalStatus status) => PostalQuery(
    name: name.text,
    phone: phone.text,
    trackingNumber: tracking.text,
    status: status,
  );

  bool get canSearch => query(PostalStatus.waiting).canSearch;

  /// 未領取 first, then 退件, then 已領取; newest first within each.
  List<PostalRecord> get records {
    const order = [
      PostalStatus.waiting,
      PostalStatus.returned,
      PostalStatus.collected,
    ];
    final all = [for (final status in order) ...?pages[status]?.records];
    all.sort((a, b) {
      final byStatus = order.indexOf(a.status) - order.indexOf(b.status);
      return byStatus != 0
          ? byStatus
          : b.receivedDate.compareTo(a.receivedDate);
    });
    return all;
  }

  bool get hasMore => pages.values.any((p) => p.nextForm != null);

  /// The student's name from the verified school profile, if any.
  String get ownName => session.profile['chName']?.toString().trim() ?? '';

  @override
  void dispose() {
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
    if (!canSearch) {
      setState(() => error = '請填寫收件人、手機號碼或郵件號碼其中一項。');
      return;
    }
    final current = ++generation;
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
      for (final status in statuses)
        () async {
          final client = clients[status] =
              (widget.service ?? PostalService.new)();
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
      searched = true;
      if (failed == statuses.length) {
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
    return NiuScrollPage(
      title: '郵件包裹',
      onRefresh: search,
      children: [
        NiuSegmented<PostalStatus?>(
          segments: [
            (null, '全部'),
            for (final s in PostalStatus.values) (s, s.label),
          ],
          value: filter,
          onChanged: (value) {
            setState(() => filter = value);
            if (canSearch) search();
          },
        ),
        const SizedBox(height: NiuSpacing.md),
        NiuCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: name,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => search(),
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: '收件人',
                  prefixIcon: Icon(NiuIcons.person),
                ),
              ),
              if (ownName.isNotEmpty && name.text.trim() != ownName)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    style: TextButton.styleFrom(padding: EdgeInsets.zero),
                    onPressed: () => setState(() => name.text = ownName),
                    icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
                    label: const Text('帶入我的姓名'),
                  ),
                ),
              Theme(
                data: theme.copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: EdgeInsets.zero,
                  title: Text('更多條件', style: theme.textTheme.titleSmall),
                  children: [
                    TextField(
                      controller: phone,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => search(),
                      decoration: const InputDecoration(labelText: '手機號碼'),
                    ),
                    const SizedBox(height: NiuSpacing.md),
                    TextField(
                      controller: tracking,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => search(),
                      decoration: const InputDecoration(labelText: '郵件號碼'),
                    ),
                    const SizedBox(height: NiuSpacing.md),
                  ],
                ),
              ),
              FilledButton.tonal(
                onPressed: loading ? null : search,
                child: const Text('查詢'),
              ),
            ],
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: NiuSpacing.lg),
          NiuBanner(
            tone: NiuTone.warning,
            message: error!,
            actionLabel: canSearch ? '再試一次' : null,
            onAction: canSearch ? search : null,
          ),
        ],
        if (loading)
          const NiuLoading(message: '正在查詢郵件')
        else if (searched)
          NiuSection(
            title: records.isEmpty
                ? '查詢結果'
                : '${records.length} 件${filter?.label ?? ''}',
            child: records.isEmpty
                ? NiuCard(
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
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final record in records)
                        Padding(
                          padding: const EdgeInsets.only(bottom: NiuSpacing.md),
                          child: _RecordCard(record: record),
                        ),
                      if (hasMore)
                        OutlinedButton(
                          onPressed: more ? null : loadMore,
                          child: Text(more ? '載入中' : '載入更多'),
                        ),
                    ],
                  ),
          ),
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
    final (tone, icon) = switch (record.status) {
      PostalStatus.waiting => (NiuTone.accent, Icons.inventory_2_outlined),
      PostalStatus.collected => (NiuTone.success, NiuIcons.success),
      PostalStatus.returned => (NiuTone.warning, Icons.undo_rounded),
    };
    return NiuCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              NiuIconTile(icon: icon, hue: NiuHue.amber),
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
