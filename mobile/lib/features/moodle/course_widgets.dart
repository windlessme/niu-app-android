import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../shared/shared.dart';
import 'course_presentation.dart';
import 'course_detail_presentation.dart';

class MoodleCourseCard extends StatelessWidget {
  const MoodleCourseCard({
    super.key,
    required this.course,
    required this.onTap,
  });
  final CoursePresentation course;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: NiuSpacing.md),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(NiuSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    CupertinoIcons.book,
                    color: theme.colorScheme.primary,
                    size: 24,
                  ),
                  const SizedBox(width: NiuSpacing.md),
                  Expanded(
                    child: Text(
                      course.title,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(width: NiuSpacing.sm),
                  Icon(
                    CupertinoIcons.chevron_right,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    CupertinoIcons.person,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: NiuSpacing.sm),
                  Expanded(
                    child: Text(
                      course.teacher,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: NiuSpacing.xs),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    CupertinoIcons.book,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: NiuSpacing.sm),
                  Expanded(
                    child: Text(
                      course.credits,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                course.code.isEmpty ? '課程代碼未提供' : course.code,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MoodleCourseInformation extends StatelessWidget {
  const MoodleCourseInformation({super.key, required this.course});
  final CoursePresentation course;
  @override
  Widget build(BuildContext context) {
    final sections = courseDetailSections(course);
    final email = RegExp(
      r'[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}',
    ).firstMatch(course.summary)?.group(0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HeroCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                course.title,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              if (course.englishName.isNotEmpty)
                SelectableText(course.englishName),
              const SizedBox(height: NiuSpacing.lg),
              SelectableText(course.code.isEmpty ? '課程代碼未提供' : course.code),
              SelectableText(course.teacher),
              SelectableText(course.credits),
              if (email != null)
                TextButton.icon(
                  icon: const Icon(CupertinoIcons.mail),
                  label: Text(email),
                  onPressed: () async {
                    try {
                      await launchUrl(Uri(scheme: 'mailto', path: email));
                    } catch (_) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('無法開啟郵件 App')),
                        );
                      }
                    }
                  },
                ),
            ],
          ),
        ),
        const SizedBox(height: NiuSpacing.xl),
        if (sections.isEmpty) const Text('校方尚未提供課程說明。'),
        for (final section in sections) ...[
          Text(section.title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: NiuSpacing.sm),
          SelectableText(section.body),
          const SizedBox(height: NiuSpacing.lg),
        ],
      ],
    );
  }
}

class MoodleModuleSegments extends StatelessWidget
    implements PreferredSizeWidget {
  const MoodleModuleSegments({super.key});
  @override
  Size get preferredSize => const Size.fromHeight(88);
  @override
  Widget build(BuildContext context) {
    final controller = DefaultTabController.of(context);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(
          NiuSpacing.lg,
          NiuSpacing.xs,
          NiuSpacing.lg,
          NiuSpacing.md,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              for (final (index, label) in [
                '公告',
                '教材',
                '作業',
                '討論',
                '成績',
                '出席',
              ].indexed)
                Semantics(
                  selected: controller.index == index,
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: TextButton(
                      style: TextButton.styleFrom(
                        minimumSize: const Size(64, 48),
                        backgroundColor: controller.index == index
                            ? Theme.of(context).colorScheme.surface
                            : Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13),
                        ),
                      ),
                      onPressed: () => controller.animateTo(
                        index,
                        duration: NiuMotion.duration(context, NiuMotion.fast),
                      ),
                      child: Text(label),
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
