import 'package:flutter/material.dart';
import '../../shared/shared.dart';
import 'moodle_repository.dart';
import '../../shared/app_tab_button.dart';

/// Each visited tab remains mounted, including its future and scroll position.
class CourseDetailTabs extends StatefulWidget {
  const CourseDetailTabs({super.key, required this.builders});
  final List<WidgetBuilder> builders;
  @override
  State<CourseDetailTabs> createState() => _CourseDetailTabsState();
}

class _CourseDetailTabsState extends State<CourseDetailTabs> {
  int selected = 0;
  final visited = <int>{0};
  static const labels = ['公告', '教材', '作業', '討論', '成績', '出席'];
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(
            NiuSpacing.lg,
            NiuSpacing.xs,
            NiuSpacing.lg,
            NiuSpacing.md,
          ),
          child: Row(
            children: [
              for (final (index, label) in labels.indexed)
                Padding(
                  padding: const EdgeInsets.only(right: NiuSpacing.sm),
                  child: AppTabButton(
                    selected: selected == index,
                    label: label,
                    icon: const [
                      Icons.campaign_outlined,
                      Icons.folder_outlined,
                      Icons.assignment_outlined,
                      Icons.forum_outlined,
                      Icons.bar_chart,
                      Icons.fact_check_outlined,
                    ][index],
                    onPressed: () => setState(() {
                      selected = index;
                      visited.add(index);
                    }),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: selected,
            children: [
              for (var index = 0; index < widget.builders.length; index++)
                visited.contains(index)
                    ? TickerMode(
                        enabled: selected == index,
                        child: Builder(builder: widget.builders[index]),
                      )
                    : const SizedBox.shrink(),
            ],
          ),
        ),
      ],
    );
  }
}

class CourseDetailList extends StatefulWidget {
  const CourseDetailList({
    super.key,
    required this.load,
    required this.item,
    required this.emptyTitle,
    required this.emptyMessage,
    this.header,
  });
  final Future<List<Json>> Function() load;
  final Widget Function(Json) item;
  final String emptyTitle, emptyMessage;
  final Widget? header;
  @override
  State<CourseDetailList> createState() => _CourseDetailListState();
}

class _CourseDetailListState extends State<CourseDetailList> {
  late Future<List<Json>> future = Future.sync(widget.load);
  List<Json>? retained;
  bool refreshing = false;
  Future<void> reload() async {
    if (refreshing) return;
    setState(() {
      refreshing = true;
      future = Future.sync(widget.load);
    });
    try {
      await future;
    } catch (_) {
      /* Error is presented below. */
    } finally {
      if (mounted) setState(() => refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Json>>(
    future: future,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.done &&
          snapshot.hasData) {
        retained = snapshot.data;
      }
      return RefreshIndicator(
        onRefresh: reload,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            NiuSpacing.lg,
            NiuSpacing.xs,
            NiuSpacing.lg,
            NiuSpacing.xxxl,
          ),
          children: [
            if (widget.header != null) widget.header!,
            if (snapshot.hasError)
              AppErrorState(
                message: retained == null ? '請檢查連線後重新讀取。' : '更新失敗，以下保留上次資料。',
                onRetry: reload,
              ),
            if (retained == null && !snapshot.hasError)
              const AppLoadingState(message: '正在讀取課程資料…'),
            if (retained != null) ...[
              if (refreshing)
                const Padding(
                  padding: EdgeInsets.all(NiuSpacing.md),
                  child: Text('正在更新，顯示上次資料…'),
                ),
              if (retained!.isEmpty)
                NiuEmptyState(
                  title: widget.emptyTitle,
                  message: widget.emptyMessage,
                ),
              ...retained!.map(widget.item),
            ],
          ],
        ),
      );
    },
  );
}

class CourseDetailItem extends StatelessWidget {
  const CourseDetailItem({
    super.key,
    required this.title,
    this.metadata,
    this.excerpt,
    this.onTap,
    this.children = const [],
  });
  final String title;
  final String? metadata, excerpt;
  final VoidCallback? onTap;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: NiuSpacing.md),
    child: AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(NiuSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          if (metadata != null && metadata!.isNotEmpty) ...[
            const SizedBox(height: NiuSpacing.sm),
            Text(
              metadata!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (excerpt != null && excerpt!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(excerpt!, maxLines: 3, overflow: TextOverflow.ellipsis),
          ],
          ...children,
        ],
      ),
    ),
  );
}
