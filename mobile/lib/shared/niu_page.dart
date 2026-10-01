import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'niu_colors.dart';
import 'niu_icons.dart';

/// Toolbar action. [tonal] adds a quiet filled circle for standalone headers.
class NiuIconButton extends StatelessWidget {
  const NiuIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.tonal = false,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool tonal;
  @override
  Widget build(BuildContext context) {
    final colors = NiuColors.of(context);
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: tonal ? colors.fill : null,
        foregroundColor: colors.ink,
        disabledForegroundColor: colors.inkTertiary,
      ),
      icon: Icon(icon, size: 22),
    );
  }
}

/// Back that also works for deep-linked routes without a history entry.
class NiuBackButton extends StatelessWidget {
  const NiuBackButton({super.key});
  @override
  Widget build(BuildContext context) => NiuIconButton(
    icon: NiuIcons.back,
    tooltip: '返回',
    onPressed: () async {
      final popped = await Navigator.of(context).maybePop();
      if (popped || !context.mounted) return;
      final router = GoRouter.maybeOf(context);
      if (router == null) return;
      router.canPop() ? router.pop() : router.go('/');
    },
  );
}

/// Standard top bar for pages whose body is not a scrolling list
/// (web views, scanners, full-screen tools).
class NiuAppBar extends StatelessWidget implements PreferredSizeWidget {
  const NiuAppBar({
    super.key,
    required this.title,
    this.actions = const [],
    this.showBack = true,
    this.bottom,
  });
  final String title;
  final List<Widget> actions;
  final bool showBack;
  final PreferredSizeWidget? bottom;
  @override
  Size get preferredSize =>
      Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? 0));
  @override
  Widget build(BuildContext context) => AppBar(
    automaticallyImplyLeading: false,
    leading: showBack ? const NiuBackButton() : null,
    titleSpacing: showBack ? NiuSpacing.xs : NiuSpacing.gutter,
    title: Semantics(
      header: true,
      child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
    ),
    actions: [
      ...actions,
      const SizedBox(width: NiuSpacing.xs),
    ],
    bottom: bottom,
  );
}

/// The canonical page: a collapsing Material top bar over a padded list.
///
/// Tab roots use [large] titles; secondary pages collapse from a medium title.
/// Content is laid out as [children] with the shared gutter, or as raw
/// [slivers] when a page needs lazy lists.
class NiuScrollPage extends StatelessWidget {
  const NiuScrollPage({
    super.key,
    required this.title,
    this.actions = const [],
    this.children = const [],
    this.slivers = const [],
    this.onRefresh,
    this.large = false,
    this.showBack = true,
    this.bottomBar,
    this.padding,
    this.controller,
    this.floatingActionButton,
  });
  final String title;
  final List<Widget> actions;
  final List<Widget> children;
  final List<Widget> slivers;
  final RefreshCallback? onRefresh;
  final bool large;
  final bool showBack;
  final Widget? bottomBar;
  final EdgeInsets? padding;
  final ScrollController? controller;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context) {
    // Edge-to-edge: keep the last item clear of gesture and navigation bars
    // even when the platform reports them only as view or gesture insets.
    final media = MediaQuery.of(context);
    final systemInset = [
      media.padding.bottom,
      media.viewPadding.bottom,
      media.systemGestureInsets.bottom,
    ].reduce((a, b) => a > b ? a : b);
    final bottomInset = bottomBar == null
        ? (NiuSpacing.xxl + systemInset).clamp(NiuSpacing.huge, double.infinity)
        : NiuSpacing.xxl;
    final header = large
        ? SliverAppBar.large(
            automaticallyImplyLeading: false,
            leading: showBack ? const NiuBackButton() : null,
            title: Semantics(header: true, child: Text(title)),
            actions: [
              ...actions,
              const SizedBox(width: NiuSpacing.xs),
            ],
          )
        : SliverAppBar.medium(
            automaticallyImplyLeading: false,
            leading: showBack ? const NiuBackButton() : null,
            title: Semantics(header: true, child: Text(title)),
            actions: [
              ...actions,
              const SizedBox(width: NiuSpacing.xs),
            ],
          );
    Widget scroll = CustomScrollView(
      controller: controller,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        header,
        if (children.isNotEmpty)
          SliverPadding(
            padding:
                padding ??
                EdgeInsets.fromLTRB(
                  NiuSpacing.gutter,
                  NiuSpacing.xs,
                  NiuSpacing.gutter,
                  slivers.isEmpty ? bottomInset : 0,
                ),
            sliver: SliverList.list(children: children),
          ),
        ...slivers,
        if (slivers.isNotEmpty)
          SliverToBoxAdapter(child: SizedBox(height: bottomInset)),
      ],
    );
    if (onRefresh != null) {
      scroll = RefreshIndicator(
        edgeOffset: large ? 152 : 112,
        onRefresh: onRefresh!,
        child: scroll,
      );
    }
    return Scaffold(
      body: SafeArea(top: false, bottom: false, child: scroll),
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: bottomBar == null
          ? null
          : NiuBottomBar(child: bottomBar!),
    );
  }
}

/// Sticky footer for a page's primary action.
class NiuBottomBar extends StatelessWidget {
  const NiuBottomBar({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Material(
    // A Material surface so rows and checkboxes inside keep their ink.
    color: NiuColors.of(context).canvas,
    shape: Border(top: BorderSide(color: NiuColors.of(context).hairline)),
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          NiuSpacing.gutter,
          NiuSpacing.md,
          NiuSpacing.gutter,
          NiuSpacing.md,
        ),
        child: child,
      ),
    ),
  );
}
