import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/analytics/app_analytics.dart';
import '../../shared/shared.dart';
import 'mail_models.dart';
import 'numail_client.dart';

/// Writes, replies to or forwards a message through a NUMail draft. Pops
/// true once the school accepted it for sending.
class MailComposeScreen extends StatefulWidget {
  const MailComposeScreen({
    super.key,
    required this.service,
    required this.kind,
    required this.initial,
    this.draft,
    this.pickFiles,
  });
  final MailService service;
  final ComposeKind kind;
  final MailDraftData initial;

  /// An existing draft being edited.
  final MailDraft? draft;

  /// Test seam for the file picker.
  final Future<List<XFile>> Function()? pickFiles;
  @override
  State<MailComposeScreen> createState() => _MailComposeScreenState();
}

class _MailComposeScreenState extends State<MailComposeScreen> {
  late final to = List<MailAddress>.of(widget.initial.to);
  late final cc = List<MailAddress>.of(widget.initial.cc);
  late final bcc = List<MailAddress>.of(widget.initial.bcc);
  late final subject = TextEditingController(text: widget.initial.subject);
  late final text = TextEditingController(text: widget.initial.text);
  final pending = {
    'to': TextEditingController(),
    'cc': TextEditingController(),
    'bcc': TextEditingController(),
  };
  late bool showCc = cc.isNotEmpty || bcc.isNotEmpty;
  late bool keepQuote = widget.initial.quote.isNotEmpty;
  late MailDraft? draft = widget.draft;
  late final files = <MailAttachment>[...?widget.draft?.attachments];
  Future<MailDraft>? creating;
  int uploading = 0;
  bool sending = false, done = false, changed = false;

  String get title => switch (widget.kind) {
    ComposeKind.reply || ComposeKind.replyAll => '回覆',
    ComposeKind.forward => '轉寄',
    ComposeKind.draft => '編輯草稿',
    ComposeKind.fresh => '寫信',
  };

  @override
  void initState() {
    super.initState();
    subject.addListener(_touch);
    text.addListener(_touch);
    // Forwarded files and quoted pictures go onto the draft right away.
    if (widget.initial.forwardAttachments.isNotEmpty) _ensureDraft();
  }

  void _touch() => changed = true;

  @override
  void dispose() {
    subject.dispose();
    text.dispose();
    for (final c in pending.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<MailDraft> _ensureDraft() => draft != null
      ? Future.value(draft)
      : creating ??= () async {
          final next = await widget.service.newDraft(
            inReplyTo: widget.initial.inReplyTo,
            references: widget.initial.references,
          );
          for (final original in widget.initial.forwardAttachments) {
            try {
              final carried = await widget.service.carry(next, original);
              if (mounted && original.cid.isEmpty) {
                setState(() => files.add(carried));
              }
            } catch (_) {
              if (mounted) {
                showNiuMessage(context, '「${original.filename}」沒有一起轉寄');
              }
            }
          }
          draft = next;
          return next;
        }().whenComplete(() => creating = null);

  /// Commits typed text in each address field.
  String? _commitPending() {
    for (final (key, list) in [('to', to), ('cc', cc), ('bcc', bcc)]) {
      final raw = pending[key]!.text.trim();
      if (raw.isEmpty) continue;
      for (final part in raw.split(RegExp(r'[,;，；\s]+'))) {
        if (part.isEmpty) continue;
        final a = MailAddress.parse(part);
        if (!a.valid) return '「$part」不是有效的電子郵件地址';
        if (!list.contains(a)) list.add(a);
      }
      pending[key]!.clear();
    }
    return null;
  }

  MailDraftData get data => MailDraftData(
    to: to,
    cc: cc,
    bcc: bcc,
    subject: subject.text.trim(),
    text: text.text,
    quote: keepQuote ? widget.initial.quote : '',
    type: widget.initial.type,
    inReplyTo: widget.initial.inReplyTo,
    references: widget.initial.references,
  );

  Future<void> attach() async {
    final picked = await (widget.pickFiles ?? () => openFiles())();
    if (picked.isEmpty || !mounted) return;
    changed = true;
    setState(() => uploading += picked.length);
    for (final file in picked) {
      try {
        final bytes = await file.readAsBytes();
        if (bytes.length > 25 * 1024 * 1024) {
          throw const MailException('單一附件不能超過 25 MB');
        }
        final d = await _ensureDraft();
        final uploaded = await widget.service.upload(d, file.name, bytes);
        if (mounted) setState(() => files.add(uploaded));
      } catch (e) {
        if (mounted) {
          showNiuMessage(
            context,
            e is MailException ? e.message : '「${file.name}」上傳失敗',
          );
        }
      } finally {
        if (mounted) setState(() => uploading--);
      }
    }
  }

  Future<void> remove(MailAttachment file) async {
    final d = draft;
    setState(() => files.remove(file));
    if (d == null) return;
    try {
      await widget.service.detach(d, file);
    } catch (_) {
      if (mounted) {
        setState(() => files.add(file));
        showNiuMessage(context, '無法移除附件，請再試一次');
      }
    }
  }

  Future<void> send() async {
    if (sending || uploading > 0) return;
    final problem = _commitPending();
    setState(() {});
    if (problem != null) return showNiuMessage(context, problem);
    if (to.isEmpty && cc.isEmpty && bcc.isEmpty) {
      return showNiuMessage(context, '請至少填寫一位收件者');
    }
    if (subject.text.trim().isEmpty &&
        !await confirmNiuAction(
          context,
          title: '沒有主旨',
          message: '確定不加主旨就寄出嗎？',
          confirmLabel: '寄出',
        )) {
      return;
    }
    setState(() => sending = true);
    try {
      final d = await _ensureDraft();
      await widget.service.send(d, data);
      AppAnalytics.instance.event('mail_send', {'result': 'success'});
      done = true;
      HapticFeedback.mediumImpact();
      if (mounted) Navigator.pop(context, true);
    } on MailUncertain catch (e) {
      // Never resent automatically: the school may already have sent it.
      AppAnalytics.instance.event('mail_send', {'result': 'unconfirmed'});
      done = true;
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('無法確認是否已寄出'),
          content: Text(e.message),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
      if (mounted) Navigator.pop(context, false);
    } catch (e) {
      AppAnalytics.instance.event('mail_send', {'result': 'failure'});
      if (!mounted) return;
      setState(() => sending = false);
      showNiuMessage(context, e is MailException ? e.message : '寄送失敗，請再試一次。');
    }
  }

  Future<bool> saveDraft() async {
    _commitPending();
    try {
      final d = await _ensureDraft();
      await widget.service.save(d, data);
      done = true;
      return true;
    } catch (e) {
      if (mounted) {
        showNiuMessage(context, e is MailException ? e.message : '草稿沒有儲存成功');
      }
      return false;
    }
  }

  Future<void> leave() async {
    final dirty =
        changed ||
        files.isNotEmpty ||
        pending.values.any((c) => c.text.trim().isNotEmpty);
    if (done || !dirty || data.isEmpty && files.isEmpty) {
      final d = draft;
      if (!done && d != null && widget.kind != ComposeKind.draft) {
        widget.service.discard(d).catchError((Object _) {});
      }
      done = true;
      if (mounted) Navigator.pop(context, false);
      return;
    }
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('要儲存草稿嗎？'),
        content: const Text('儲存後可在「草稿」繼續編輯。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'discard'),
            child: Text(widget.kind == ComposeKind.draft ? '不儲存' : '捨棄'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'stay'),
            child: const Text('繼續編輯'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'save'),
            child: const Text('儲存草稿'),
          ),
        ],
      ),
    );
    if (!mounted || choice == null || choice == 'stay') return;
    if (choice == 'save') {
      if (!await saveDraft()) return;
      if (mounted) showNiuMessage(context, '已儲存草稿');
    } else {
      final d = draft;
      if (d != null && widget.kind != ComposeKind.draft) {
        widget.service.discard(d).catchError((Object _) {});
      }
      done = true;
    }
    if (mounted) Navigator.pop(context, false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = NiuColors.of(context);
    final busy = sending || uploading > 0;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !sending) leave();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: '關閉',
            icon: const Icon(NiuIcons.close),
            onPressed: sending ? null : leave,
          ),
          title: Text(title),
          actions: [
            IconButton(
              tooltip: '加入附件',
              icon: const Icon(NiuIcons.attach),
              onPressed: sending ? null : attach,
            ),
            Padding(
              padding: const EdgeInsets.only(right: NiuSpacing.sm),
              child: FilledButton.icon(
                onPressed: busy ? null : send,
                icon: sending
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded, size: 18),
                label: Text(sending ? '寄送中' : '寄出'),
              ),
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: AbsorbPointer(
            absorbing: sending,
            child: ListView(
              padding: const EdgeInsets.only(bottom: NiuSpacing.huge),
              children: [
                _AddressField(
                  label: '收件者',
                  list: to,
                  pending: pending['to']!,
                  onChanged: () => setState(() => changed = true),
                  trailing: showCc
                      ? null
                      : TextButton(
                          onPressed: () => setState(() => showCc = true),
                          child: const Text('副本'),
                        ),
                ),
                if (showCc) ...[
                  _AddressField(
                    label: '副本',
                    list: cc,
                    pending: pending['cc']!,
                    onChanged: () => setState(() => changed = true),
                  ),
                  _AddressField(
                    label: '密件副本',
                    list: bcc,
                    pending: pending['bcc']!,
                    onChanged: () => setState(() => changed = true),
                  ),
                ],
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: NiuSpacing.gutter,
                  ),
                  child: TextField(
                    controller: subject,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      hintText: '主旨',
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                    ),
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                Divider(height: 1, color: colors.hairline),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: NiuSpacing.gutter,
                  ),
                  child: TextField(
                    controller: text,
                    minLines: 8,
                    maxLines: null,
                    keyboardType: TextInputType.multiline,
                    autofocus:
                        widget.kind != ComposeKind.fresh &&
                        widget.kind != ComposeKind.forward,
                    decoration: const InputDecoration(
                      hintText: '內容',
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                    ),
                  ),
                ),
                if (uploading > 0 || files.isNotEmpty)
                  Padding(
                    padding: NiuLayout.page(context, top: NiuSpacing.md),
                    child: Wrap(
                      spacing: NiuSpacing.sm,
                      runSpacing: NiuSpacing.sm,
                      children: [
                        for (final f in files)
                          InputChip(
                            avatar: const Icon(NiuIcons.attach, size: 18),
                            label: Text(
                              '${f.filename} · ${formatBytes(f.size)}',
                              overflow: TextOverflow.ellipsis,
                            ),
                            onDeleted: sending ? null : () => remove(f),
                            deleteButtonTooltipMessage: '移除附件',
                          ),
                        if (uploading > 0)
                          Chip(
                            avatar: const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            label: Text('正在上傳 $uploading 個檔案'),
                          ),
                      ],
                    ),
                  ),
                if (widget.initial.quote.isNotEmpty)
                  Padding(
                    padding: NiuLayout.page(context, top: NiuSpacing.lg),
                    child: NiuWell(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Material(
                            type: MaterialType.transparency,
                            child: SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              value: keepQuote,
                              onChanged: (v) => setState(() {
                                keepQuote = v;
                                changed = true;
                              }),
                              title: Text(
                                widget.kind == ComposeKind.forward
                                    ? '附上轉寄的原信'
                                    : '附上原信內容',
                              ),
                            ),
                          ),
                          if (keepQuote)
                            Text(
                              htmlToText(widget.initial.quote),
                              maxLines: 6,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall,
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Recipients as chips; typing a comma, space or Enter adds the address.
class _AddressField extends StatelessWidget {
  const _AddressField({
    required this.label,
    required this.list,
    required this.pending,
    required this.onChanged,
    this.trailing,
  });
  final String label;
  final List<MailAddress> list;
  final TextEditingController pending;
  final VoidCallback onChanged;
  final Widget? trailing;

  void _commit(BuildContext context, String raw) {
    final parts = raw.split(RegExp(r'[,;，；\s]+')).where((p) => p.isNotEmpty);
    final rest = <String>[];
    for (final part in parts) {
      final a = MailAddress.parse(part);
      if (a.valid) {
        if (!list.contains(a)) list.add(a);
      } else {
        rest.add(part);
      }
    }
    pending.text = rest.join(' ');
    pending.selection = TextSelection.collapsed(offset: pending.text.length);
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = NiuColors.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.hairline)),
      ),
      padding: const EdgeInsets.fromLTRB(
        NiuSpacing.gutter,
        NiuSpacing.xs,
        NiuSpacing.sm,
        NiuSpacing.xs,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 64,
            constraints: const BoxConstraints(minHeight: 48),
            alignment: Alignment.centerLeft,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.inkSecondary,
              ),
            ),
          ),
          Expanded(
            child: Wrap(
              spacing: NiuSpacing.xs,
              runSpacing: NiuSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final a in list)
                  InputChip(
                    label: Text(a.display),
                    tooltip: a.address,
                    visualDensity: VisualDensity.compact,
                    onDeleted: () {
                      list.remove(a);
                      onChanged();
                    },
                    deleteButtonTooltipMessage: '移除 ${a.address}',
                  ),
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 120),
                  child: IntrinsicWidth(
                    child: TextField(
                      controller: pending,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        hintText: list.isEmpty ? '輸入電子郵件地址' : null,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: false,
                        isDense: true,
                      ),
                      onChanged: (value) {
                        if (RegExp(r'[,;，；\s]$').hasMatch(value)) {
                          _commit(context, value);
                        }
                      },
                      onSubmitted: (value) => _commit(context, value),
                      onTapOutside: (_) {
                        if (pending.text.trim().isNotEmpty) {
                          _commit(context, pending.text);
                        }
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
