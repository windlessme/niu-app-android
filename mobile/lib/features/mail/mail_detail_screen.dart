import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../shared/shared.dart';
import 'mail_body_view.dart';
import 'mail_compose_screen.dart';
import 'mail_format.dart';
import 'mail_models.dart';
import 'numail_client.dart';

/// What happened to a message while it was open, for the list to follow.
enum MailOutcome { removed, unread }

/// One message: header, body, attachments, and reply/forward.
class MailDetailScreen extends StatefulWidget {
  const MailDetailScreen({
    super.key,
    required this.service,
    required this.summary,
    required this.folders,
    required this.me,
    this.bodyBuilder,
  });
  final MailService service;
  final MailSummary summary;
  final List<MailFolder> folders;

  /// The reader's own address, so replies skip it.
  final String me;

  /// Test seam for the WebView body.
  final Widget Function(MailMessage message, bool remote)? bodyBuilder;
  @override
  State<MailDetailScreen> createState() => _MailDetailScreenState();
}

class _MailDetailScreenState extends State<MailDetailScreen> {
  MailMessage? message;
  String? error;
  bool remoteImages = false, busy = false, scaled = false;
  final downloading = <int>{};
  Directory? temp;

  MailSummary get s => widget.summary;

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    final dir = temp;
    if (dir != null) dir.delete(recursive: true).catchError((Object _) => dir);
    super.dispose();
  }

  Future<void> load() async {
    setState(() => error = null);
    try {
      final m = await widget.service.open(s.box, s.uid);
      if (!mounted) return;
      setState(() => message = m);
      // Opening marks it read, as the school site does.
      if (!m.seen) {
        widget.service.setSeen(s.box, [s.uid], true).catchError((Object _) {});
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = e is MailException ? e.message : '無法開啟這封信。');
      }
    }
  }

  Future<void> act(
    Future<void> Function() action,
    MailOutcome outcome,
    String done,
  ) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
      if (!mounted) return;
      showNiuMessage(context, done);
      Navigator.pop(context, outcome);
    } catch (e) {
      if (mounted) {
        showNiuMessage(
          context,
          e is MailException ? e.message : '操作沒有成功，請再試一次。',
        );
        setState(() => busy = false);
      }
    }
  }

  Future<void> delete() async {
    final trash = s.box == MailFolder.trash || s.box == MailFolder.drafts;
    if (trash &&
        !await confirmNiuAction(
          context,
          title: '永久刪除這封信？',
          message: '刪除後無法復原。',
          confirmLabel: '刪除',
          destructive: true,
        )) {
      return;
    }
    await act(
      () => trash
          ? widget.service.delete(s.box, [s.uid])
          : widget.service.move(s.box, [s.uid], MailFolder.trash),
      MailOutcome.removed,
      trash ? '已永久刪除' : '已移到垃圾桶',
    );
  }

  Future<void> move() async {
    final target = await pickMailFolder(
      context,
      widget.folders.where((f) => f.name != s.box).toList(),
    );
    if (target == null) return;
    await act(
      () => widget.service.move(s.box, [s.uid], target.name),
      MailOutcome.removed,
      '已移到「${target.label}」',
    );
  }

  Future<void> compose(ComposeKind kind) async {
    final m = message;
    if (m == null) return;
    final data = MailDraftData.answer(
      m,
      kind,
      me: widget.me,
      dateLabel: m.date == null ? '' : formatMailDateLong(m.date!),
    );
    final sent = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => MailComposeScreen(
          service: widget.service,
          kind: kind,
          initial: data,
        ),
      ),
    );
    if (sent == true && mounted) showNiuMessage(context, '已寄出');
  }

  Future<void> download(MailAttachment file) async {
    if (!downloading.add(file.id)) return;
    setState(() {});
    try {
      final bytes = await widget.service.attachment(s.box, s.uid, file);
      final root = await getTemporaryDirectory();
      temp ??= await Directory('${root.path}/numail-').createTemp();
      final name = file.filename.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final path = '${temp!.path}/$name';
      await File(path).writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(path, mimeType: file.contentType)],
          title: name,
        ),
      );
    } catch (e) {
      if (mounted) {
        showNiuMessage(
          context,
          e is MailException ? e.message : '附件下載失敗，請再試一次。',
        );
      }
    } finally {
      downloading.remove(file.id);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = message;
    return NiuScrollPage(
      // The subject heads the message itself; the bar names the folder.
      title: MailFolder(s.box).label,
      actions: [
        if (m != null) ...[
          NiuIconButton(
            icon: Icons.delete_outline_rounded,
            tooltip: s.box == MailFolder.trash ? '永久刪除' : '刪除',
            onPressed: busy ? null : delete,
          ),
          PopupMenuButton<String>(
            tooltip: '更多',
            enabled: !busy,
            onSelected: (value) => switch (value) {
              'unread' => act(
                () => widget.service.setSeen(s.box, [s.uid], false),
                MailOutcome.unread,
                '已標為未讀',
              ),
              'move' => move(),
              _ => null,
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'unread', child: Text('標為未讀')),
              PopupMenuItem(value: 'move', child: Text('移到其他信件匣')),
            ],
          ),
        ],
      ],
      onRefresh: load,
      bottomBar: m == null || s.box == MailFolder.drafts
          ? null
          : Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () => compose(ComposeKind.reply),
                    icon: const Icon(Icons.reply_rounded),
                    label: const Text('回覆'),
                  ),
                ),
                const SizedBox(width: NiuSpacing.sm),
                if (m.to.length + m.cc.length > 1) ...[
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: () => compose(ComposeKind.replyAll),
                      icon: const Icon(Icons.reply_all_rounded),
                      label: const Text('全部回覆'),
                    ),
                  ),
                  const SizedBox(width: NiuSpacing.sm),
                ],
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () => compose(ComposeKind.forward),
                    icon: const Icon(Icons.forward_rounded),
                    label: const Text('轉寄'),
                  ),
                ),
              ],
            ),
      children: [
        if (error != null)
          NiuError(title: '無法開啟信件', message: error!, onRetry: load)
        else if (m == null)
          const NiuLoading(message: '正在開啟信件')
        else ...[
          _Header(message: m),
          const SizedBox(height: NiuSpacing.lg),
          if (!remoteImages && hasRemoteImages(m.html)) ...[
            NiuBanner(
              tone: NiuTone.neutral,
              icon: Icons.image_not_supported_outlined,
              message: '已封鎖外部圖片，避免寄件者追蹤你是否讀信。',
              actionLabel: '顯示圖片',
              onAction: () => setState(() => remoteImages = true),
            ),
            const SizedBox(height: NiuSpacing.md),
          ],
          if (scaled)
            Padding(
              padding: const EdgeInsets.only(bottom: NiuSpacing.xs),
              child: Row(
                children: [
                  Icon(
                    Icons.zoom_out_map_rounded,
                    size: 16,
                    color: NiuColors.of(context).inkTertiary,
                  ),
                  const SizedBox(width: NiuSpacing.xs),
                  Expanded(
                    child: Text(
                      '已縮小以符合螢幕寬度',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => MailOriginalScreen(
                          title: m.subject.isEmpty ? '（無主旨）' : m.subject,
                          html: m.html,
                          showRemoteImages: remoteImages,
                        ),
                      ),
                    ),
                    child: const Text('原始大小'),
                  ),
                ],
              ),
            ),
          widget.bodyBuilder?.call(m, remoteImages) ??
              MailBodyView(
                onScaled: (value) {
                  if (mounted && value != scaled) {
                    setState(() => scaled = value);
                  }
                },
                html: m.html,
                cookies: widget.service.cookies,
                showRemoteImages: remoteImages,
                onMailto: (address) => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => MailComposeScreen(
                      service: widget.service,
                      kind: ComposeKind.fresh,
                      initial: MailDraftData(to: [MailAddress.parse(address)]),
                    ),
                  ),
                ),
              ),
          if (m.files.isNotEmpty)
            NiuSection(
              title: '附件',
              subtitle: '${m.files.length} 個檔案',
              child: NiuGroup(
                children: [
                  for (final f in m.files)
                    NiuRow(
                      title: f.filename,
                      subtitle: formatBytes(f.size),
                      icon: attachmentIcon(f.contentType),
                      hue: NiuHue.indigo,
                      trailing: downloading.contains(f.id)
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(NiuIcons.download),
                      chevron: false,
                      onTap: () => download(f),
                    ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

IconData attachmentIcon(String type) => type.startsWith('image/')
    ? Icons.image_outlined
    : type.contains('pdf')
    ? Icons.picture_as_pdf_outlined
    : type.startsWith('video/')
    ? Icons.movie_outlined
    : NiuIcons.attach;

class _Header extends StatefulWidget {
  const _Header({required this.message});
  final MailMessage message;
  @override
  State<_Header> createState() => _HeaderState();
}

class _HeaderState extends State<_Header> {
  bool details = false;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = NiuColors.of(context);
    final m = widget.message;
    final from = m.from.isEmpty ? null : m.from.first;
    String people(List<MailAddress> list) => list
        .map((a) => a.name.isEmpty ? a.address : '${a.name} <${a.address}>')
        .join('、');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SelectableText(
          m.subject.isEmpty ? '（無主旨）' : m.subject,
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: NiuSpacing.md),
        InkWell(
          borderRadius: BorderRadius.circular(NiuRadius.md),
          onTap: () => setState(() => details = !details),
          child: Row(
            children: [
              MailAvatar(name: from?.display ?? '?'),
              const SizedBox(width: NiuSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      from?.display ?? '（未知寄件者）',
                      style: theme.textTheme.titleSmall,
                    ),
                    Text(
                      [
                        if (m.date != null) formatMailDateLong(m.date!),
                        '寄給 ${m.to.isEmpty ? '（無）' : m.to.first.display}'
                            '${m.to.length + m.cc.length > 1 ? ' 等 ${m.to.length + m.cc.length} 人' : ''}',
                      ].join(' · '),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Icon(
                details ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                color: colors.inkTertiary,
              ),
            ],
          ),
        ),
        if (details)
          Padding(
            padding: const EdgeInsets.only(top: NiuSpacing.sm),
            child: NiuWell(
              child: Column(
                children: [
                  if (from != null)
                    NiuKeyValue(label: '寄件者', value: people(m.from)),
                  NiuKeyValue(label: '收件者', value: people(m.to)),
                  if (m.cc.isNotEmpty)
                    NiuKeyValue(label: '副本', value: people(m.cc)),
                  if (m.bcc.isNotEmpty)
                    NiuKeyValue(label: '密件副本', value: people(m.bcc)),
                  if (m.date != null)
                    NiuKeyValue(
                      label: '日期',
                      value: formatMailDateLong(m.date!),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
