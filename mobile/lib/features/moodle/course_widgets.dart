import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../shared/shared.dart';
import 'course_presentation.dart';
import 'course_detail_presentation.dart';

const _courseHues = [
  NiuHue.blue,
  NiuHue.purple,
  NiuHue.teal,
  NiuHue.orange,
  NiuHue.indigo,
  NiuHue.green,
  NiuHue.pink,
  NiuHue.cyan,
];

/// Stable per-course colour so a course looks the same everywhere.
NiuHue courseHue(CoursePresentation course) {
  final key = course.code.isEmpty ? course.title : course.code;
  var hash = 0;
  for (final unit in key.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return _courseHues[hash % _courseHues.length];
}

String semesterLabel(String term) =>
    term.length == 4 ? '${term.substring(0, 3)} 學年第 ${term[3]} 學期' : term;

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
    final colors = NiuColors.of(context);
    final hue = courseHue(course);
    final meta = [
      if (course.teacher != '教師未提供') course.teacher,
      if (course.credits != '學分未提供') course.credits,
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: NiuSpacing.md),
      child: NiuCard(
        onTap: onTap,
        padding: EdgeInsets.zero,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: hue.foreground(context)),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    NiuSpacing.lg,
                    14,
                    NiuSpacing.sm,
                    14,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              course.title,
                              style: theme.textTheme.titleMedium,
                            ),
                            if (meta.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                meta.join(' · '),
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                            if (course.code.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                course.code,
                                style: theme.textTheme.labelSmall,
                              ),
                            ],
                            // Moodle's own completion tracking, as on iOS.
                            if (num.tryParse('${course.source['progress']}')
                                case final progress? when progress > 0) ...[
                              const SizedBox(height: NiuSpacing.sm),
                              NiuProgressBar(
                                value: progress / 100,
                                height: 4,
                                semanticLabel: '完成進度',
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '完成進度 ${progress.round()}%',
                                style: theme.textTheme.labelSmall,
                              ),
                            ],
                            if (course.source['hidden'] == true) ...[
                              const SizedBox(height: NiuSpacing.xs),
                              Row(
                                children: [
                                  Icon(
                                    Icons.visibility_off_outlined,
                                    size: 14,
                                    color: colors.inkTertiary,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '已隱藏',
                                    style: theme.textTheme.labelSmall,
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      Icon(NiuIcons.forward, color: colors.inkTertiary),
                    ],
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

class MoodleCourseInformation extends StatelessWidget {
  const MoodleCourseInformation({super.key, required this.course});
  final CoursePresentation course;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sections = courseDetailSections(course);
    final email = RegExp(
      r'[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}',
    ).firstMatch(course.summary)?.group(0);
    final hue = courseHue(course);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NiuCard(
          padding: const EdgeInsets.all(NiuSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              NiuIconTile(icon: NiuIcons.course, hue: hue),
              const SizedBox(height: NiuSpacing.md),
              SelectableText(
                course.title,
                style: theme.textTheme.headlineSmall,
              ),
              if (course.englishName.isNotEmpty) ...[
                const SizedBox(height: 2),
                SelectableText(
                  course.englishName,
                  style: theme.textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: NiuSpacing.lg),
              Wrap(
                spacing: NiuSpacing.sm,
                runSpacing: NiuSpacing.sm,
                children: [
                  NiuTag(label: course.teacher, icon: NiuIcons.person),
                  NiuTag(label: course.credits),
                  NiuTag(label: course.code.isEmpty ? '課程代碼未提供' : course.code),
                ],
              ),
              if (email != null) ...[
                const SizedBox(height: NiuSpacing.md),
                TextButton.icon(
                  style: TextButton.styleFrom(padding: EdgeInsets.zero),
                  icon: const Icon(Icons.mail_outline_rounded, size: 18),
                  label: Text(email),
                  onPressed: () async {
                    try {
                      await launchUrl(Uri(scheme: 'mailto', path: email));
                    } catch (_) {
                      if (context.mounted) {
                        showNiuMessage(context, '無法開啟郵件 App');
                      }
                    }
                  },
                ),
              ],
            ],
          ),
        ),
        if (sections.isEmpty)
          Padding(
            padding: const EdgeInsets.all(NiuSpacing.lg),
            child: Text('老師還沒有提供課程說明。', style: theme.textTheme.bodySmall),
          )
        else
          NiuSection(
            title: '課程說明',
            child: NiuCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final (i, section) in sections.indexed) ...[
                    if (i > 0) const SizedBox(height: NiuSpacing.lg),
                    Text(section.title, style: theme.textTheme.titleSmall),
                    const SizedBox(height: NiuSpacing.xs),
                    SelectableText(
                      section.body,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ],
              ),
            ),
          ),
        const SizedBox(height: NiuSpacing.section),
      ],
    );
  }
}
