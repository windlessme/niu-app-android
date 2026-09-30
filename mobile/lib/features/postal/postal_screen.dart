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
  PostalStatus status = PostalStatus.waiting;
  PostalService? service;
  PostalPage? page;
  List<PostalRecord> records = const [];
  bool loading = false, more = false;
  String? error;
  int generation = 0;

  PostalQuery get query => PostalQuery(
    name: name.text,
    phone: phone.text,
    trackingNumber: tracking.text,
    status: status,
  );

  @override
  void initState() {
    super.initState();
    final own = session.profile['chName']?.toString().trim() ?? '';
    name.text = own;
    if (own.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => search());
    }
  }

  @override
  void dispose() {
    generation++;
    service?.close();
    name.dispose();
    phone.dispose();
    tracking.dispose();
    super.dispose();
  }

  Future<void> search() async {
    FocusScope.of(context).unfocus();
    final q = query.normalized;
    if (!q.canSearch) {
      setState(() => error = '請填寫收件人、手機號碼或郵件號碼其中一項。');
      return;
    }
    final current = ++generation;
    service?.close();
    final client = service = (widget.service ?? PostalService.new)();
    setState(() {
      loading = true;
      error = null;
      page = null;
      records = const [];
    });
    try {
      final result = await client.search(q);
      if (!mounted || current != generation) return;
      setState(() {
        page = result;
        records = result.records;
      });
    } catch (e) {
      if (!mounted || current != generation) return;
      setState(
        () => error = e is PostalException ? e.message : '無法取得郵件資料，稍後再試一次。',
      );
    } finally {
      if (mounted && current == generation) setState(() => loading = false);
    }
  }

  Future<void> loadMore() async {
    final current = generation;
    final client = service, last = page;
    if (client == null || last?.nextForm == null || more) return;
    setState(() => more = true);
    try {
      final next = await client.nextPage(last!);
      if (!mounted || current != generation) return;
      final known = records.map((r) => r.id).toSet();
      setState(() {
        page = next;
        records = [
          ...records,
          ...next.records.where((r) => !known.contains(r.id)),
        ];
      });
    } catch (e) {
      if (!mounted || current != generation) return;
      setState(() => error = e is PostalException ? e.message : '無法載入更多結果');
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
        NiuSegmented<PostalStatus>(
          segments: [for (final s in PostalStatus.values) (s, s.label)],
          value: status,
          onChanged: (value) {
            setState(() => status = value);
            if (query.canSearch) search();
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
                decoration: const InputDecoration(
                  labelText: '收件人',
                  prefixIcon: Icon(NiuIcons.person),
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
            actionLabel: query.canSearch ? '再試一次' : null,
            onAction: query.canSearch ? search : null,
          ),
        ],
        if (loading)
          const NiuLoading(message: '正在查詢郵件')
        else if (page != null)
          NiuSection(
            title: records.isEmpty
                ? '查詢結果'
                : '${records.length} 件${page!.query.status.label}',
            child: records.isEmpty
                ? NiuCard(
                    child: NiuEmpty(
                      padding: const EdgeInsets.symmetric(
                        vertical: NiuSpacing.xl,
                      ),
                      icon: Icons.inventory_2_outlined,
                      title: switch (page!.query.status) {
                        PostalStatus.waiting => '沒有待領取的郵件',
                        PostalStatus.collected => '沒有已領取的紀錄',
                        PostalStatus.returned => '沒有退件紀錄',
                      },
                      message: '有新郵件時，學校通常會另外通知。',
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
                      if (page!.nextForm != null)
                        OutlinedButton(
                          onPressed: more ? null : loadMore,
                          child: Text(more ? '載入中' : '載入更多'),
                        ),
                    ],
                  ),
          ),
        const SizedBox(height: NiuSpacing.xl),
        Text(
          '領取地點、時間與所需證件以學校通知為準。\n資料來源：國立宜蘭大學郵務收發管理系統',
          textAlign: TextAlign.center,
          style: theme.textTheme.labelMedium,
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
