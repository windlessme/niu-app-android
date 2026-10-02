import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
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

  @override
  void didUpdateWidget(CampusShell old) {
    super.didUpdateWidget(old);
    // A tab tap or a link moved the shell: follow it unless a swipe did.
    final index = widget.shell.currentIndex;
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
      child: Scaffold(
        body: PageView(
          controller: pages,
          onPageChanged: (i) {
            if (i != widget.shell.currentIndex) widget.shell.goBranch(i);
          },
          children: widget.children,
        ),
        bottomNavigationBar: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: colors.hairline, width: .8)),
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
