import 'package:flutter/material.dart';
import '../../shared/shared.dart';
import 'course_detail_widgets.dart';
import 'moodle_repository.dart';
import 'moodle_links.dart';

class MoodleForumScreen extends StatefulWidget {
  const MoodleForumScreen({
    super.key,
    required this.repository,
    required this.forum,
  });
  final MoodleRepository repository;
  final Json forum;
  @override
  State<MoodleForumScreen> createState() => _MoodleForumScreenState();
}

class _MoodleForumScreenState extends State<MoodleForumScreen> {
  int page = 0;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: NiuAppBar(title: plain(widget.forum['name'])),
    body: CourseDetailList(
      emptyIcon: NiuIcons.forum,
      emptyTitle: '沒有討論主題',
      emptyMessage: '這個討論區還沒有主題，或這一頁已經沒有更多討論。',
      key: ValueKey(page),
      load: () =>
          widget.repository.discussions(number(widget.forum['id']), page: page),
      header: Padding(
        padding: const EdgeInsets.only(bottom: NiuSpacing.md),
        child: Row(
          children: [
            NiuIconButton(
              tooltip: '上一頁',
              icon: Icons.chevron_left_rounded,
              tonal: true,
              onPressed: page > 0 ? () => setState(() => page--) : null,
            ),
            Expanded(
              child: Text(
                '第 ${page + 1} 頁',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            NiuIconButton(
              tooltip: '下一頁',
              icon: Icons.chevron_right_rounded,
              tonal: true,
              onPressed: () => setState(() => page++),
            ),
          ],
        ),
      ),
      item: (d) => CourseDetailItem(
        title: plain(d['subject'] ?? d['name']),
        metadata:
            '${plain(d['userfullname']).isEmpty ? '作者未提供' : plain(d['userfullname'])} · ${campusTime(d['timemodified'])} · ${d['numreplies'] == null ? '回覆數未提供' : '${d['numreplies']} 則回覆'}',
        excerpt: plain(d['message']),
        onTap: () => pushMoodle(
          context,
          MoodleDiscussionScreen(repository: widget.repository, discussion: d),
        ),
      ),
    ),
  );
}

class MoodleDiscussionScreen extends StatelessWidget {
  const MoodleDiscussionScreen({
    super.key,
    required this.repository,
    required this.discussion,
  });
  final MoodleRepository repository;
  final Json discussion;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: NiuAppBar(
      title: plain(discussion['subject'] ?? discussion['name']),
    ),
    body: CourseDetailList(
      emptyIcon: NiuIcons.forum,
      emptyTitle: '沒有貼文',
      emptyMessage: '這個主題目前沒有可以顯示的內容。',
      load: () => repository.posts(
        number(discussion['discussion'] ?? discussion['id']),
      ),
      item: (p) {
        final theme = Theme.of(context);
        final author = plain(p['author'] is Map ? p['author']['fullname'] : '');
        return Padding(
          padding: const EdgeInsets.only(bottom: NiuSpacing.md),
          child: NiuCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: NiuColors.of(context).accentSoft,
                      child: Text(
                        author.characters.firstOrNull ?? '?',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: NiuColors.of(context).accent,
                        ),
                      ),
                    ),
                    const SizedBox(width: NiuSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            author.isEmpty ? '作者未提供' : author,
                            style: theme.textTheme.titleSmall,
                          ),
                          Text(
                            campusTime(p['timecreated']),
                            style: theme.textTheme.labelMedium,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: NiuSpacing.md),
                if (plain(p['subject']).isNotEmpty) ...[
                  Text(plain(p['subject']), style: theme.textTheme.titleMedium),
                  const SizedBox(height: NiuSpacing.xs),
                ],
                SelectableText(plain(p['message'])),
                for (final f in objects(p['attachments'] ?? []))
                  MoodleAttachmentButton(
                    name: plain(f['filename']),
                    onPressed: () => openMoodleUrl(
                      context,
                      repository,
                      '${f['fileurl']}',
                      plain(f['filename']),
                      file: true,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
