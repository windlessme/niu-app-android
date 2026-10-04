import 'package:flutter/material.dart';
import '../../core/platform/app_version.dart';
import '../../shared/shared.dart';
import 'announcement_board.dart';
import 'announcement_repository.dart';

/// Every announcement in effect, including ones closed on home.
class AnnouncementsScreen extends StatefulWidget {
  const AnnouncementsScreen({super.key, this.repository, this.version});
  final Future<AnnouncementRepository>? repository;
  final Future<String?>? version;
  @override
  State<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends State<AnnouncementsScreen> {
  List<Announcement>? items;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load({bool force = false}) async {
    final repository = await (widget.repository ?? sharedAnnouncements());
    final version =
        await (widget.version ?? AppVersion.current().then((v) => v?.name));
    void show(AnnouncementDocument d) {
      if (!mounted) return;
      final now = DateTime.now();
      setState(
        () => items = [
          for (final a in d.announcements)
            if (a.visible(now: now, version: version)) a,
        ],
      );
    }

    show(await repository.local());
    show(await repository.refresh(force: force));
  }

  @override
  Widget build(BuildContext context) {
    final list = items;
    return NiuScrollPage(
      title: '公告',
      onRefresh: () => load(force: true),
      children: [
        if (list == null)
          const NiuLoading(message: '正在讀取公告')
        else if (list.isEmpty)
          const NiuCard(
            child: NiuEmpty(
              padding: EdgeInsets.symmetric(vertical: NiuSpacing.xxl),
              icon: Icons.campaign_outlined,
              title: '目前沒有公告',
              message: '有新消息時會顯示在首頁。',
            ),
          )
        else
          for (final a in list)
            Padding(
              padding: const EdgeInsets.only(bottom: NiuSpacing.md),
              child: AnnouncementCard(
                announcement: a,
                onOpen: () => openAnnouncement(context, a),
              ),
            ),
      ],
    );
  }
}

void openAnnouncement(BuildContext context, Announcement a) => Navigator.of(
  context,
).push(MaterialPageRoute<void>(builder: (_) => AnnouncementDetailScreen(a)));

class AnnouncementDetailScreen extends StatelessWidget {
  const AnnouncementDetailScreen(this.announcement, {super.key});
  final Announcement announcement;
  @override
  Widget build(BuildContext context) {
    final a = announcement;
    final text = Theme.of(context).textTheme;
    String day(DateTime d) => '${d.year}/${d.month}/${d.day}';
    return NiuScrollPage(
      title: '公告',
      children: [
        NiuCard(
          padding: const EdgeInsets.all(NiuSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (a.level == AnnouncementLevel.warning) ...[
                const NiuBadge(label: '重要', tone: NiuTone.warning),
                const SizedBox(height: NiuSpacing.sm),
              ],
              Text(a.title, style: text.headlineSmall),
              if (a.start != null || a.end != null) ...[
                const SizedBox(height: NiuSpacing.xs),
                Text(
                  [
                    if (a.start != null) day(a.start!),
                    if (a.end != null) '${day(a.end!)} 止',
                  ].join(' – '),
                  style: text.labelMedium?.copyWith(
                    fontFeatures: tabularFigures,
                  ),
                ),
              ],
              const SizedBox(height: NiuSpacing.lg),
              SelectableText(a.body, style: text.bodyLarge),
              if (a.url != null) ...[
                const SizedBox(height: NiuSpacing.xl),
                FilledButton.tonalIcon(
                  onPressed: () => openPublicUrl(context, a.url!),
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: Text(a.linkLabel ?? '開啟連結'),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
