import 'package:flutter/material.dart';
import '../../shared/shared.dart';
import 'moodle_repository.dart';

/// Tabs that swipe sideways. Each visited tab stays mounted, including its
/// future and scroll position; an unvisited one loads when it comes into view.
class CourseDetailTabs extends StatefulWidget {
  const CourseDetailTabs({super.key, required this.builders});
  final List<WidgetBuilder> builders;
  @override
  State<CourseDetailTabs> createState() => _CourseDetailTabsState();
}

class _CourseDetailTabsState extends State<CourseDetailTabs> {
  int selected = 0;
  final pages = PageController();
  static const labels = ['公告', '教材', '作業', '問答', '討論', '成績', '出席'];

  @override
  void dispose() {
    pages.dispose();
    super.dispose();
  }

  void select(int index) {
    setState(() => selected = index);
    final duration = NiuMotion.duration(context);
    // A far tab jumps, so the tabs in between do not load on the way.
    if ((index - (pages.page ?? 0)).abs() > 1 || duration == Duration.zero) {
      pages.jumpToPage(index);
    } else {
      pages.animateToPage(index, duration: duration, curve: NiuMotion.curve);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      NiuTabs(labels: labels, selected: selected, onChanged: select),
      Divider(height: 1, color: NiuColors.of(context).hairline),
      Expanded(
        child: PageView.builder(
          controller: pages,
          itemCount: widget.builders.length,
          onPageChanged: (index) => setState(() => selected = index),
          itemBuilder: (context, index) =>
              _KeepAlive(child: Builder(builder: widget.builders[index])),
        ),
      ),
    ],
  );
}

class _KeepAlive extends StatefulWidget {
  const _KeepAlive({required this.child});
  final Widget child;
  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

class CourseDetailList extends StatefulWidget {
  const CourseDetailList({
    super.key,
    required this.load,
    required this.item,
    required this.emptyTitle,
    required this.emptyMessage,
    this.emptyIcon = NiuIcons.info,
    this.header,
  });
  final Future<List<Json>> Function() load;
  final Widget Function(Json) item;
  final String emptyTitle, emptyMessage;
  final IconData emptyIcon;
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
            NiuSpacing.gutter,
            NiuSpacing.lg,
            NiuSpacing.gutter,
            NiuSpacing.huge,
          ),
          children: [
            if (widget.header != null) widget.header!,
            if (snapshot.hasError && retained == null)
              NiuError(message: '檢查網路連線後再試一次。', onRetry: reload),
            if (snapshot.hasError && retained != null)
              Padding(
                padding: const EdgeInsets.only(bottom: NiuSpacing.md),
                child: NiuBanner(
                  tone: NiuTone.warning,
                  message: '更新失敗，先顯示上次的資料。',
                  actionLabel: '再試一次',
                  onAction: reload,
                ),
              ),
            if (retained == null && !snapshot.hasError)
              const NiuLoading(message: '正在讀取課程資料'),
            if (retained != null) ...[
              if (refreshing)
                const Padding(
                  padding: EdgeInsets.only(bottom: NiuSpacing.md),
                  child: NiuSyncStatus(updatedAt: null, refreshing: true),
                ),
              if (retained!.isEmpty)
                NiuEmpty(
                  icon: widget.emptyIcon,
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

/// A card for announcements, assignments, discussions and grade items.
class CourseDetailItem extends StatelessWidget {
  const CourseDetailItem({
    super.key,
    required this.title,
    this.metadata,
    this.excerpt,
    this.onTap,
    this.badge,
    this.children = const [],
  });
  final String title;
  final String? metadata, excerpt;
  final VoidCallback? onTap;
  final Widget? badge;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: NiuSpacing.md),
      child: NiuCard(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (badge != null) ...[
              Align(alignment: Alignment.centerLeft, child: badge),
              const SizedBox(height: NiuSpacing.sm),
            ],
            Text(title, style: theme.textTheme.titleMedium),
            if (metadata != null && metadata!.isNotEmpty) ...[
              const SizedBox(height: NiuSpacing.xs),
              Text(metadata!, style: theme.textTheme.labelMedium),
            ],
            if (excerpt != null && excerpt!.isNotEmpty) ...[
              const SizedBox(height: NiuSpacing.sm),
              Text(
                excerpt!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: NiuColors.of(context).inkSecondary,
                ),
              ),
            ],
            ...children,
          ],
        ),
      ),
    );
  }
}
