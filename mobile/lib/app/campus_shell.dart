import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../shared/shared.dart';

class CampusShell extends StatelessWidget {
  const CampusShell({super.key, required this.child, required this.path});
  final Widget child;
  final String path;

  static const destinations = [
    ('首頁', NiuIcons.home, NiuIcons.homeSelected, '/'),
    ('課表', NiuIcons.schedule, NiuIcons.scheduleSelected, '/schedule'),
    ('M 園區', NiuIcons.moodle, NiuIcons.moodleSelected, '/moodle'),
  ];

  @override
  Widget build(BuildContext context) {
    final selected = destinations.indexWhere((item) => item.$4 == path);
    final colors = NiuColors.of(context);
    return Scaffold(
      body: child,
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: colors.hairline, width: .8)),
        ),
        child: NavigationBar(
          selectedIndex: selected < 0 ? 0 : selected,
          onDestinationSelected: (i) => context.go(destinations[i].$4),
          destinations: [
            for (final item in destinations)
              NavigationDestination(
                icon: Icon(item.$2),
                selectedIcon: Icon(item.$3),
                label: item.$1,
                tooltip: '',
              ),
          ],
        ),
      ),
    );
  }
}
