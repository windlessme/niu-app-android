import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/platform/app_version.dart';
import '../../shared/shared.dart';
import 'announcement_repository.dart';
import 'announcements_screen.dart';

Future<AnnouncementRepository>? _shared;

/// The app's one repository, cached under application support.
Future<AnnouncementRepository> sharedAnnouncements() => _shared ??= () async {
  try {
    final support = await getApplicationSupportDirectory();
    return AnnouncementRepository(
      cacheDirectory: Directory('${support.path}/public_announcements'),
    );
  } catch (_) {
    return AnnouncementRepository();
  }
}();

/// Which announcements this device has closed on home or already shown as
/// a dialog. Ids only; nothing about the student.
class AnnouncementMemory {
  static const _dismissed = 'announcementsDismissed';
  static const _shown = 'announcementsShown';

  static Future<Set<String>> dismissed() => _read(_dismissed);
  static Future<Set<String>> shown() => _read(_shown);
  static Future<void> dismiss(String id) => _add(_dismissed, id);
  static Future<void> markShown(String id) => _add(_shown, id);

  static Future<Set<String>> _read(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return {...?prefs.getStringList(key)};
    } catch (_) {
      return {};
    }
  }

  static Future<void> _add(String key, String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = [...?prefs.getStringList(key)]..remove(id);
      list.add(id);
      // Old ids are only kept so they do not reappear; 200 is plenty.
      await prefs.setStringList(
        key,
        list.length > 200 ? list.sublist(list.length - 200) : list,
      );
    } catch (_) {}
  }
}

/// Home's announcement cards, and the one-time dialog for popup notices.
class AnnouncementBoard extends StatefulWidget {
  const AnnouncementBoard({super.key, this.repository, this.version, this.now});
  final Future<AnnouncementRepository>? repository;

  /// Installed version name; read from the platform when null.
  final Future<String?>? version;
  final DateTime Function()? now;
  @override
  State<AnnouncementBoard> createState() => _AnnouncementBoardState();
}

class _AnnouncementBoardState extends State<AnnouncementBoard> {
  List<Announcement> visible = [];
  Set<String> dismissed = {};
  String? version;
  bool _dialogOpen = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final repository = await (widget.repository ?? sharedAnnouncements());
    version =
        await (widget.version ?? AppVersion.current().then((v) => v?.name));
    dismissed = await AnnouncementMemory.dismissed();
    _show(await repository.local());
    _show(await repository.refresh());
  }

  void _show(AnnouncementDocument document) {
    if (!mounted) return;
    final now = (widget.now ?? DateTime.now)();
    setState(() {
      visible = [
        for (final a in document.announcements)
          if (a.visible(now: now, version: version)) a,
      ];
    });
    unawaited(_popups());
  }

  Future<void> _popups() async {
    if (_dialogOpen) return;
    final shown = await AnnouncementMemory.shown();
    for (final a in visible.where((a) => a.popup && !shown.contains(a.id))) {
      if (!mounted || ModalRoute.of(context)?.isCurrent == false) return;
      _dialogOpen = true;
      await AnnouncementMemory.markShown(a.id);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: Text(a.title),
          content: SingleChildScrollView(child: Text(a.body)),
          actions: [
            if (a.url != null)
              TextButton(
                onPressed: () => openPublicUrl(dialog, a.url!),
                child: Text(a.linkLabel ?? '開啟連結'),
              ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
      _dialogOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cards = visible.where((a) => !dismissed.contains(a.id)).toList();
    if (cards.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: NiuSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, a) in cards.take(2).indexed) ...[
            if (i > 0) const SizedBox(height: NiuSpacing.sm),
            AnnouncementCard(
              announcement: a,
              onOpen: () => openAnnouncement(context, a),
              onClose: () {
                setState(() => dismissed = {...dismissed, a.id});
                unawaited(AnnouncementMemory.dismiss(a.id));
              },
            ),
          ],
          if (cards.length > 2)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        AnnouncementsScreen(repository: widget.repository),
                  ),
                ),
                child: Text('全部公告（${cards.length}）'),
              ),
            ),
        ],
      ),
    );
  }
}

/// A compact notice: title, the start of the text, and a close button.
class AnnouncementCard extends StatelessWidget {
  const AnnouncementCard({
    super.key,
    required this.announcement,
    required this.onOpen,
    this.onClose,
  });
  final Announcement announcement;
  final VoidCallback onOpen;
  final VoidCallback? onClose;
  @override
  Widget build(BuildContext context) {
    final a = announcement;
    final text = Theme.of(context).textTheme;
    final colors = NiuColors.of(context);
    final warning = a.level == AnnouncementLevel.warning;
    final fg = warning ? colors.warning : colors.accent;
    return Material(
      color: warning ? NiuTone.warning.background(context) : colors.accentSoft,
      borderRadius: BorderRadius.circular(NiuRadius.lg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            NiuSpacing.lg,
            NiuSpacing.md,
            NiuSpacing.xs,
            NiuSpacing.md,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  warning
                      ? Icons.warning_amber_rounded
                      : Icons.campaign_rounded,
                  color: fg,
                  size: 22,
                ),
              ),
              const SizedBox(width: NiuSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      a.title,
                      style: text.titleSmall?.copyWith(color: colors.ink),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      a.body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall?.copyWith(
                        color: colors.inkSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (onClose != null)
                IconButton(
                  tooltip: '關閉這則公告',
                  visualDensity: VisualDensity.compact,
                  onPressed: onClose,
                  icon: Icon(Icons.close_rounded, color: colors.inkTertiary),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
