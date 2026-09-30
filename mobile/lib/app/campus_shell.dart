import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../features/home/campus_services.dart';
import '../shared/shared.dart';

class CampusShell extends StatelessWidget {
  const CampusShell({super.key, required this.child, required this.path});
  final Widget child;
  final String path;

  static const destinations = [
    ('首頁', NiuIcons.home, NiuIcons.homeSelected, '/'),
    ('課表', NiuIcons.schedule, NiuIcons.scheduleSelected, '/schedule'),
    ('M 園區', NiuIcons.moodle, NiuIcons.moodleSelected, '/moodle'),
    ('校園', NiuIcons.campus, NiuIcons.campusSelected, '/campus'),
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

class CampusServicesScreen extends StatelessWidget {
  const CampusServicesScreen({super.key});
  @override
  Widget build(BuildContext context) => NiuScrollPage(
    title: '校園服務',
    large: true,
    showBack: false,
    children: [
      for (final (i, group) in CampusServices.groups.indexed) ...[
        Padding(
          padding: EdgeInsets.fromLTRB(
            NiuSpacing.xs,
            i == 0 ? NiuSpacing.sm : NiuSpacing.section,
            NiuSpacing.xs,
            NiuSpacing.md,
          ),
          child: Semantics(
            header: true,
            child: Text(
              group.$1,
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ),
        NiuGroup(
          children: [
            for (final service in group.$2)
              NiuRow(
                title: service.title,
                subtitle: service.subtitle,
                icon: service.icon,
                hue: service.hue,
                onTap: () => openCampusService(context, service),
              ),
          ],
        ),
      ],
      const SizedBox(height: NiuSpacing.xxl),
      Text(
        '非官方工具，校務資訊以學校系統為準。',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ],
  );
}
