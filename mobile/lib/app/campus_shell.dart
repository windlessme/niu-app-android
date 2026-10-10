import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../core/analytics/app_analytics.dart';
import '../shared/shared.dart';

/// The three root tabs. Each keeps its own state while the others are
/// shown, and a sideways swipe moves to the neighbouring tab.
class CampusShell extends StatefulWidget {
  const CampusShell({super.key, required this.shell, required this.children});
  final StatefulNavigationShell shell;
  final List<Widget> children;

  static const destinations = [
    ('首頁', NiuIcons.home, NiuIcons.homeSelected, '/'),
    ('課表', NiuIcons.schedule, NiuIcons.scheduleSelected, '/schedule'),
    ('M 園區', NiuIcons.moodle, NiuIcons.moodleSelected, '/moodle'),
  ];

  /// The tab route around [branches], one per [destinations] entry. Every
  /// branch is built up front so a swipe never reveals an empty page.
  static StatefulShellRoute route(List<StatefulShellBranch> branches) =>
      StatefulShellRoute(
        builder: (_, _, shell) => shell,
        navigatorContainerBuilder: (_, shell, children) =>
            CampusShell(shell: shell, children: children),
        branches: branches,
      );

  @override
  State<CampusShell> createState() => _CampusShellState();
}

class _CampusShellState extends State<CampusShell> {
  late final pages = PageController(initialPage: widget.shell.currentIndex);
  static const _screens = ['home', 'schedule', 'moodle'];

  @override
  void initState() {
    super.initState();
    AppAnalytics.instance.screen(_screens[widget.shell.currentIndex]);
  }

  @override
  void didUpdateWidget(CampusShell old) {
    super.didUpdateWidget(old);
    // A tab tap or a link moved the shell: follow it unless a swipe did.
    final index = widget.shell.currentIndex;
    if (index != old.shell.currentIndex) {
      AppAnalytics.instance.screen(_screens[index]);
    }
    if (!pages.hasClients || pages.page?.round() == index) return;
    final from = pages.page!.round();
    final duration = NiuMotion.duration(context);
    if ((index - from).abs() > 1 || duration == Duration.zero) {
      pages.jumpToPage(index);
    } else {
      pages.animateToPage(index, duration: duration, curve: NiuMotion.curve);
    }
  }

  @override
  void dispose() {
    pages.dispose();
    super.dispose();
  }

  void select(int index) => widget.shell.goBranch(
    index,
    // Tapping the current tab returns it to its first page.
    initialLocation: index == widget.shell.currentIndex,
  );

  Widget _pages() => PageView(
    controller: pages,
    onPageChanged: (i) {
      if (i != widget.shell.currentIndex) widget.shell.goBranch(i);
    },
    children: widget.children,
  );

  /// Tablets and landscape: the tabs sit in a side rail, and the pages are
  /// told their real width so they size their readable column from it.
  Widget _railLayout(BuildContext context, int selected, NiuColors colors) {
    final media = MediaQuery.of(context);
    const rail = 88.0;
    return Scaffold(
      body: Row(
        children: [
          SafeArea(
            right: false,
            child: NavigationRail(
              minWidth: rail,
              selectedIndex: selected,
              onDestinationSelected: select,
              labelType: NavigationRailLabelType.all,
              groupAlignment: -0.9,
              destinations: [
                for (final item in CampusShell.destinations)
                  NavigationRailDestination(
                    icon: Icon(item.$2),
                    selectedIcon: Icon(item.$3),
                    label: Text(item.$1),
                  ),
              ],
            ),
          ),
          VerticalDivider(width: .8, thickness: .8, color: colors.hairline),
          Expanded(
            child: MediaQuery(
              data: media.copyWith(
                size: Size(
                  media.size.width - rail - media.padding.left - .8,
                  media.size.height,
                ),
                padding: media.padding.copyWith(left: 0),
                viewPadding: media.viewPadding.copyWith(left: 0),
              ),
              child: _pages(),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.shell.currentIndex;
    final colors = NiuColors.of(context);
    // Back on another tab returns home before leaving the app.
    return PopScope(
      canPop: selected == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) select(0);
      },
      child: NiuLayout.isWide(context)
          ? _railLayout(context, selected, colors)
          : Scaffold(
              body: _pages(),
              bottomNavigationBar: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: colors.hairline, width: .8),
                  ),
                ),
                child: NavigationBar(
                  selectedIndex: selected,
                  onDestinationSelected: select,
                  destinations: [
                    for (final item in CampusShell.destinations)
                      NavigationDestination(
                        icon: Icon(item.$2),
                        selectedIcon: Icon(item.$3),
                        label: item.$1,
                        tooltip: '',
                      ),
                  ],
                ),
              ),
            ),
    );
  }
}
