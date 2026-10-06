import 'package:flutter/material.dart';
import '../../shared/shared.dart';
import 'moodle_assignment_screen.dart';
import 'moodle_links.dart';
import 'moodle_repository.dart';
import 'moodle_upcoming.dart';

/// Loads and keeps the 即將截止 list for one set of courses.
class UpcomingController extends ChangeNotifier {
  UpcomingController(this.repository, {DateTime Function()? clock})
    : clock = clock ?? DateTime.now;
  final MoodleRepository repository;
  final DateTime Function() clock;

  Map<int, String> _courses = {};
  List<UpcomingAssignment>? items;
  bool loading = false, failed = false;
  DateTime now = DateTime.now();
  int _generation = 0;

  /// Loads when the course set changed; keeps the list otherwise.
  void show(Map<int, String> courses) {
    final same =
        courses.length == _courses.length &&
        courses.keys.every(_courses.containsKey);
    if (same && (items != null || loading)) return;
    _courses = courses;
    items = null;
    reload();
  }

  Future<void> reload() async {
    final generation = ++_generation;
    loading = true;
    failed = false;
    now = clock();
    notifyListeners();
    try {
      final result = await loadUpcoming(repository, _courses, now: now);
      if (generation != _generation) return;
      items = result;
    } catch (_) {
      if (generation != _generation) return;
      failed = true;
    }
    loading = false;
    notifyListeners();
  }

  Future<void> open(BuildContext context, UpcomingAssignment item) async {
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) => MoodleAssignmentScreen(
          repository: repository,
          assignment: item.assignment,
        ),
      ),
    );
    // The student may have just handed it in.
    await reload();
  }
}

/// The collapsible 即將截止 card at the top of M 園區, like the iOS app.
class MoodleUpcomingSection extends StatefulWidget {
  const MoodleUpcomingSection({super.key, required this.controller});
  final UpcomingController controller;
  @override
  State<MoodleUpcomingSection> createState() => _MoodleUpcomingSectionState();
}

class _MoodleUpcomingSectionState extends State<MoodleUpcomingSection> {
  bool expanded = true;
  static const preview = 5;

  String? get status {
    final c = widget.controller;
    if (c.items == null) {
      return c.failed ? '載入失敗，展開後可重試' : '正在載入待繳作業…';
    }
    if (c.items!.isEmpty) return '近兩週沒有待繳作業';
    return c.failed ? '更新失敗，保留上次資料；展開後可重試' : null;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      final theme = Theme.of(context);
      final colors = NiuColors.of(context);
      final items = c.items ?? const <UpcomingAssignment>[];
      return NiuCard(
        padding: const EdgeInsets.symmetric(
          horizontal: NiuSpacing.lg,
          vertical: NiuSpacing.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              button: true,
              expanded: expanded,
              label: '即將截止',
              value: status ?? '${items.length} 份待繳作業',
              excludeSemantics: true,
              child: InkWell(
                borderRadius: BorderRadius.circular(NiuRadius.md),
                onTap: () => setState(() => expanded = !expanded),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44),
                  child: Row(
                    children: [
                      Text('即將截止', style: theme.textTheme.titleMedium),
                      if (c.items != null && items.isNotEmpty) ...[
                        const SizedBox(width: NiuSpacing.sm),
                        NiuBadge(label: '${items.length}'),
                      ],
                      const Spacer(),
                      AnimatedRotation(
                        turns: expanded ? 0 : -0.25,
                        duration: const Duration(milliseconds: 200),
                        child: Icon(
                          Icons.expand_more_rounded,
                          color: colors.inkSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (!expanded && status != null)
              Padding(
                padding: const EdgeInsets.only(bottom: NiuSpacing.sm),
                child: Text(status!, style: theme.textTheme.bodySmall),
              ),
            if (expanded)
              UpcomingContent(
                controller: c,
                children: [
                  for (final item in items.take(preview))
                    UpcomingRow(
                      item: item,
                      now: c.now,
                      onTap: () => c.open(context, item),
                    ),
                  if (items.length > preview)
                    NiuRow(
                      title: '查看全部（${items.length}）',
                      onTap: () => pushMoodle(
                        context,
                        MoodleUpcomingScreen(controller: c),
                      ),
                    ),
                ],
              ),
          ],
        ),
      );
    },
  );
}

/// Loading, empty and failure states shared by the card and the full list.
class UpcomingContent extends StatelessWidget {
  const UpcomingContent({
    super.key,
    required this.controller,
    required this.children,
  });
  final UpcomingController controller;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final theme = Theme.of(context);
    Widget retry(String message) => Padding(
      padding: const EdgeInsets.only(bottom: NiuSpacing.sm),
      child: Row(
        children: [
          Icon(
            Icons.error_outline_rounded,
            size: 18,
            color: NiuColors.of(context).inkSecondary,
          ),
          const SizedBox(width: NiuSpacing.sm),
          Expanded(child: Text(message, style: theme.textTheme.bodyMedium)),
          TextButton(
            onPressed: c.loading ? null : c.reload,
            child: const Text('重試'),
          ),
        ],
      ),
    );
    if (c.items == null) {
      return c.failed
          ? retry('待繳作業載入失敗')
          : const Padding(
              padding: EdgeInsets.only(bottom: NiuSpacing.sm),
              child: NiuLoading(message: '載入待繳作業中', compact: true),
            );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (c.failed) retry('更新失敗，保留上次資料'),
        if (c.items!.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: NiuSpacing.sm),
            child: Row(
              children: [
                Icon(
                  Icons.check_circle_outline_rounded,
                  size: 18,
                  color: NiuColors.of(context).success,
                ),
                const SizedBox(width: NiuSpacing.sm),
                Text('近兩週沒有待繳作業', style: theme.textTheme.bodyMedium),
              ],
            ),
          )
        else
          ...children,
      ],
    );
  }
}

class UpcomingRow extends StatelessWidget {
  const UpcomingRow({
    super.key,
    required this.item,
    required this.now,
    required this.onTap,
  });
  final UpcomingAssignment item;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final group = UpcomingRules.group(item.due, now);
    final (icon, hue) = switch (group) {
      UpcomingGroup.overdue => (Icons.error_outline_rounded, NiuHue.red),
      UpcomingGroup.today => (Icons.schedule_rounded, NiuHue.orange),
      _ => (NiuIcons.assignment, NiuHue.blue),
    };
    return NiuRow(
      icon: icon,
      hue: hue,
      title: item.name,
      subtitle: '${UpcomingRules.deadline(item.due, now)} · ${item.courseName}',
      onTap: onTap,
    );
  }
}

/// Every pending assignment, grouped by when it is due.
class MoodleUpcomingScreen extends StatelessWidget {
  const MoodleUpcomingScreen({super.key, required this.controller});
  final UpcomingController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final items = controller.items ?? const <UpcomingAssignment>[];
      final groups = [
        for (final group in UpcomingGroup.values)
          (
            group,
            [
              for (final item in items)
                if (UpcomingRules.group(item.due, controller.now) == group)
                  item,
            ],
          ),
      ].where((g) => g.$2.isNotEmpty);
      return NiuScrollPage(
        title: '即將截止',
        onRefresh: controller.reload,
        children: [
          Padding(
            padding: const EdgeInsets.only(
              left: NiuSpacing.xs,
              bottom: NiuSpacing.md,
            ),
            child: Text(
              '逾期 7 天內與未來 14 天的待繳作業',
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
          UpcomingContent(
            controller: controller,
            children: [
              for (final (group, list) in groups)
                NiuSection(
                  title: group.label,
                  first: identical(group, groups.first.$1),
                  child: NiuGroup(
                    children: [
                      for (final item in list)
                        UpcomingRow(
                          item: item,
                          now: controller.now,
                          onTap: () => controller.open(context, item),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      );
    },
  );
}
