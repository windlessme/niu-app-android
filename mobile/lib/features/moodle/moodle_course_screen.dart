import 'package:flutter/material.dart';
import '../../shared/shared.dart';
import 'course_presentation.dart';
import 'course_widgets.dart';
import 'course_resource_tile.dart';
import 'course_detail_presentation.dart';
import 'course_detail_widgets.dart';
import '../attendance/attendance_screen.dart';
import 'moodle_repository.dart';
import 'moodle_assignment_screen.dart';
import 'moodle_forum_screen.dart';
import 'moodle_module_open.dart';
import 'moodle_links.dart';
import 'moodle_question_screen.dart';
import 'moodle_questions.dart';

class MoodleCourseScreen extends StatelessWidget {
  const MoodleCourseScreen({
    super.key,
    required this.repository,
    required this.course,
  });
  final MoodleRepository repository;
  final Json course;
  int get id => number(course['id']);
  Future<List<Json>> loadAssignments() async {
    final assignments = sortCourseAssignments(await repository.assignments(id));
    return Future.wait(
      assignments.map((assignment) async {
        try {
          final detail = await repository.submission(number(assignment['id']));
          final attempt = detail['lastattempt'];
          final submission = attempt is Map ? attempt['submission'] : null;
          return <String, dynamic>{
            ...assignment,
            if (submission is Map) 'submissionstatus': submission['status'],
            if (attempt is Map && attempt['graded'] is bool)
              'graded': attempt['graded'],
          };
        } catch (_) {
          // A missing status must not hide the assignment or imply non-submission.
          return assignment;
        }
      }),
    );
  }

  Widget discussion(BuildContext context, Json d) => CourseDetailItem(
    title: plain(d['subject'] ?? d['name']),
    metadata:
        '${plain(d['userfullname']).isEmpty ? '作者未提供' : plain(d['userfullname'])} · ${campusTime(d['timemodified'] ?? d['timecreated'])}',
    excerpt: plain(d['message']),
    children: [
      for (final file in objects(d['attachments'] ?? []))
        MoodleAttachmentButton(
          name: plain(file['filename']),
          onPressed: file['fileurl'] is String
              ? () => openMoodleUrl(
                  context,
                  repository,
                  file['fileurl'],
                  plain(file['filename']),
                  file: true,
                )
              : null,
        ),
    ],
    onTap: () => pushMoodle(
      context,
      MoodleDiscussionScreen(repository: repository, discussion: d),
    ),
  );

  Widget assignment(BuildContext context, Json a) {
    final status =
        a['submissionstatus'] ??
        (a['submission'] is Map ? a['submission']['status'] : null);
    return CourseDetailItem(
      badge: Wrap(
        spacing: NiuSpacing.sm,
        runSpacing: NiuSpacing.xs,
        children: [
          NiuBadge(
            label: submissionLabel(status),
            tone: submissionTone(status),
          ),
          if (a['graded'] is bool)
            NiuBadge(
              label: a['graded'] == true ? '已評分' : '尚未評分',
              tone: a['graded'] == true ? NiuTone.success : NiuTone.neutral,
            ),
        ],
      ),
      title: plain(a['name']),
      metadata: '截止 ${campusTime(a['duedate'])}',
      onTap: () => pushMoodle(
        context,
        MoodleAssignmentScreen(repository: repository, assignment: a),
      ),
    );
  }

  Widget grade(BuildContext context, Json g) {
    final theme = Theme.of(context);
    final value = gradeValue(g['gradeformatted']);
    final published = value != '未提供';
    return Padding(
      padding: const EdgeInsets.only(bottom: NiuSpacing.md),
      child: NiuCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    plain(g['itemname']).isEmpty
                        ? '課程總成績'
                        : plain(g['itemname']),
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                const SizedBox(width: NiuSpacing.md),
                Text(
                  published ? value : '尚未公布',
                  style:
                      (published
                              ? theme.textTheme.headlineSmall
                              : theme.textTheme.titleSmall?.copyWith(
                                  color: NiuColors.of(context).inkTertiary,
                                ))
                          ?.copyWith(fontFeatures: tabularFigures),
                ),
              ],
            ),
            const SizedBox(height: NiuSpacing.sm),
            NiuKeyValue(label: '範圍', value: gradeValue(g['rangeformatted'])),
            NiuKeyValue(
              label: '百分比',
              value: gradeValue(g['percentageformatted']),
            ),
            NiuKeyValue(label: '權重', value: gradeValue(g['weightformatted'])),
            if (plain(g['feedback']).isNotEmpty) ...[
              const SizedBox(height: NiuSpacing.sm),
              NiuWell(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('老師回饋', style: theme.textTheme.labelMedium),
                    const SizedBox(height: NiuSpacing.xs),
                    SelectableText(plain(g['feedback'])),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: const NiuAppBar(title: '課程'),
    body: CourseDetailTabs(
      builders: [
        (context) => CourseDetailList(
          emptyIcon: NiuIcons.announcement,
          emptyTitle: '還沒有公告',
          emptyMessage: '老師發布的消息會出現在這裡。',
          header: MoodleCourseInformation(course: CoursePresentation(course)),
          load: () => repository.announcements(id),
          item: (d) => discussion(context, d),
        ),
        (context) => CourseDetailList(
          emptyIcon: NiuIcons.folder,
          emptyTitle: '還沒有教材',
          emptyMessage: '老師上傳的講義和資源會依週次排在這裡。',
          load: () async => (await repository.contents(id))
              .where(
                (s) =>
                    objects(s['modules']).isNotEmpty ||
                    plain(s['summary']).isNotEmpty,
              )
              .toList(),
          item: (s) => Padding(
            padding: const EdgeInsets.only(bottom: NiuSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(
                    left: NiuSpacing.xs,
                    bottom: NiuSpacing.sm,
                  ),
                  child: Semantics(
                    header: true,
                    child: Text(
                      courseDateRange(plain(s['name'])),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                ),
                if (plain(s['summary']).isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: NiuSpacing.sm),
                    child: NiuWell(
                      padding: const EdgeInsets.all(NiuSpacing.lg),
                      child: SelectableText(plain(s['summary'])),
                    ),
                  ),
                if (objects(s['modules']).isNotEmpty)
                  NiuGroup(
                    children: [
                      for (final m in objects(s['modules']))
                        CourseResourceTile(
                          module: m,
                          onTap: () =>
                              openMoodleModule(context, repository, id, m),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        (context) => CourseDetailList(
          emptyIcon: NiuIcons.assignment,
          emptyTitle: '沒有作業',
          emptyMessage: '老師指派的作業會依截止時間排在這裡。',
          load: loadAssignments,
          item: (a) => assignment(context, a),
        ),
        (context) => CourseDetailList(
          emptyIcon: Icons.quiz_outlined,
          emptyTitle: '目前沒有問答活動',
          emptyMessage: '老師開放的測驗、即時問答、選擇與問卷會出現在這裡。',
          header: Padding(
            padding: const EdgeInsets.only(bottom: NiuSpacing.md),
            child: Text(
              '選擇活動後，可以在 App 內查看題目與作答。開放時間、提交與結果以 M 園區為準。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          load: () async => [
            for (final s in moodleQuestionSections(
              await repository.contents(id),
            ))
              {'name': s.name, 'modules': s.modules},
          ],
          item: (s) => Padding(
            padding: const EdgeInsets.only(bottom: NiuSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(
                    left: NiuSpacing.xs,
                    bottom: NiuSpacing.sm,
                  ),
                  child: Text(
                    courseDateRange(plain(s['name'])),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                NiuGroup(
                  children: [
                    for (final m in objects(s['modules']))
                      NiuRow(
                        icon: Icons.quiz_outlined,
                        hue: NiuHue.pink,
                        title: plain(m['name']),
                        subtitle: MoodleQuestionKind.entry(m) == null
                            ? '尚未開放或未符合存取條件'
                            : MoodleQuestionKind.of(m)!.title,
                        onTap: MoodleQuestionKind.entry(m) == null
                            ? null
                            : () => pushMoodle(
                                context,
                                MoodleQuestionScreen(
                                  repository: repository,
                                  module: m,
                                ),
                              ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        (context) => CourseDetailList(
          emptyIcon: NiuIcons.forum,
          emptyTitle: '沒有討論區',
          emptyMessage: '課程開放的討論區會出現在這裡。',
          load: () => repository.forums(id),
          item: (f) => CourseDetailItem(
            title: plain(f['name']),
            excerpt: plain(f['intro']),
            onTap: () => pushMoodle(
              context,
              MoodleForumScreen(repository: repository, forum: f),
            ),
          ),
        ),
        (context) => CourseDetailList(
          emptyIcon: NiuIcons.grades,
          emptyTitle: '還沒有成績',
          emptyMessage: '老師公布的評分項目會出現在這裡。',
          load: () => repository.grades(id),
          item: (g) => grade(context, g),
        ),
        (context) => AttendanceRecords(repository: repository, courseId: id),
      ],
    ),
  );
}
