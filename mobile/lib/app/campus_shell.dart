import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../shared/shared.dart';

class CampusShell extends StatelessWidget {
  const CampusShell({super.key, required this.child, required this.path});
  final Widget child;
  final String path;

  @override
  Widget build(BuildContext context) {
    const destinations = [
      ('首頁', NiuIcons.home, '/'),
      ('課表', NiuIcons.schedule, '/schedule'),
      ('M 園區', NiuIcons.moodle, '/moodle'),
      ('校園', Icons.grid_view_outlined, '/campus'),
    ];
    final scheme = Theme.of(context).colorScheme;
    final selected = destinations.indexWhere((item) => item.$3 == path);
    return Scaffold(
      body: child,
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          color: NiuColors.of(context).navigationSurface,
          border: Border(
            top: BorderSide(color: scheme.outlineVariant, width: .5),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < destinations.length; i++)
                Expanded(
                  child: Semantics(
                    selected: selected == i,
                    button: true,
                    label: destinations[i].$1,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => context.go(destinations[i].$3),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 66),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 10,
                          ),
                          child: ExcludeSemantics(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  destinations[i].$2,
                                  size: 24,
                                  color: selected == i
                                      ? scheme.primary
                                      : scheme.onSurfaceVariant,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  destinations[i].$1,
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.labelMedium
                                      ?.copyWith(
                                        color: selected == i
                                            ? scheme.primary
                                            : scheme.onSurfaceVariant,
                                        fontWeight: selected == i
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class CampusServicesScreen extends StatelessWidget {
  const CampusServicesScreen({super.key});
  static const services = [
    ('學年度行事曆', '校園重要日程與學年度安排', CupertinoIcons.calendar, '/calendar'),
    ('圖書館通行碼', '門禁 QR Code 與借書條碼', CupertinoIcons.barcode, '/library'),
    ('快速點名', '掃描課堂 QR Code', CupertinoIcons.qrcode_viewfinder, '/attendance'),
    ('歷年成績', '歷年修課、成績與 GPA', CupertinoIcons.chart_bar, '/grades'),
    ('畢業門檻', '多元時數、英文與體適能', CupertinoIcons.checkmark_seal, '/graduation'),
    ('註冊資訊', '註冊查詢與在學證明 PDF', CupertinoIcons.doc_text, '/registration'),
    ('活動報名', '活動資訊與報名紀錄', CupertinoIcons.ticket, '/events'),
    ('設定', '帳號、外觀與支援', CupertinoIcons.gear, '/settings'),
  ];
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: const IosPageHeader(title: '校園服務'),
    body: SafeArea(
      top: false,
      child: ListView.separated(
        padding: const EdgeInsets.all(20),
        itemCount: services.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final item = services[index];
          return Card(
            child: InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: () => context.push(item.$4),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Icon(item.$3, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.$1,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            item.$2,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      CupertinoIcons.chevron_right,
                      size: 18,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}
