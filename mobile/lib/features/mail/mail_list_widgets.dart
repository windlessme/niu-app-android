import 'package:flutter/material.dart';
import '../../shared/shared.dart';
import 'mail_format.dart';
import 'mail_models.dart';

class MailTile extends StatelessWidget {
  const MailTile({
    super.key,
    required this.mail,
    required this.sentBox,
    required this.now,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });
  final MailSummary mail;
  final bool sentBox, selected;
  final DateTime now;
  final VoidCallback onTap, onLongPress;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = NiuColors.of(context);
    final people = sentBox ? mail.to : mail.from;
    final who = people.isEmpty
        ? '（無）'
        : '${sentBox ? '寄給 ' : ''}${people.first.display}'
              '${people.length > 1 ? ' 等 ${people.length} 人' : ''}';
    final unread = !mail.seen && !sentBox;
    final weight = unread ? FontWeight.w700 : FontWeight.w400;
    return Semantics(
      selected: selected,
      label:
          '${unread ? '未讀，' : ''}$who，${mail.subject.isEmpty ? '無主旨' : mail.subject}'
          '${mail.hasAttachment ? '，有附件' : ''}'
          '${mail.date == null ? '' : '，${formatMailDateLong(mail.date!)}'}',
      excludeSemantics: true,
      button: true,
      child: Material(
        color: selected ? colors.accentSoft : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: NiuSpacing.gutter,
              vertical: NiuSpacing.md,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                selected
                    ? CircleAvatar(
                        radius: 20,
                        backgroundColor: colors.accent,
                        child: Icon(
                          Icons.check_rounded,
                          color: colors.onAccent,
                        ),
                      )
                    : MailAvatar(
                        name: people.isEmpty ? '?' : people.first.display,
                      ),
                const SizedBox(width: NiuSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              who,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: unread
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                          ),
                          if (mail.hasAttachment)
                            Padding(
                              padding: const EdgeInsets.only(
                                left: NiuSpacing.xs,
                              ),
                              child: Icon(
                                NiuIcons.attach,
                                size: 16,
                                color: colors.inkTertiary,
                              ),
                            ),
                          if (mail.date != null) ...[
                            const SizedBox(width: NiuSpacing.sm),
                            Text(
                              formatMailDateShort(mail.date!, now),
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: unread ? colors.accent : null,
                                fontWeight: unread ? FontWeight.w700 : null,
                                fontFeatures: tabularFigures,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              mail.subject.isEmpty ? '（無主旨）' : mail.subject,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: weight,
                                color: colors.ink,
                              ),
                            ),
                          ),
                          if (unread)
                            Container(
                              width: 8,
                              height: 8,
                              margin: const EdgeInsets.only(
                                left: NiuSpacing.sm,
                              ),
                              decoration: BoxDecoration(
                                color: colors.accent,
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
                      if (mail.preview.isNotEmpty)
                        Text(
                          mail.preview,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                    ],
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

/// 上一頁 · 第 x / y 頁 · 下一頁, plus which messages are shown.
class MailPager extends StatelessWidget {
  const MailPager({
    super.key,
    required this.page,
    required this.pages,
    required this.total,
    required this.first,
    required this.last,
    required this.loading,
    required this.onPrevious,
    required this.onNext,
    required this.onPick,
  });
  final int page, pages, total, first, last;
  final bool loading;
  final VoidCallback onPrevious, onNext;
  final VoidCallback? onPick;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NiuSpacing.gutter,
        NiuSpacing.md,
        NiuSpacing.gutter,
        NiuSpacing.huge + NiuSpacing.xl,
      ),
      child: Column(
        children: [
          if (pages > 1)
            Row(
              children: [
                IconButton.filledTonal(
                  tooltip: '上一頁',
                  onPressed: loading || page <= 1 ? null : onPrevious,
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Expanded(
                  child: Center(
                    child: TextButton(
                      onPressed: loading ? null : onPick,
                      child: loading
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              '第 $page / $pages 頁',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontFeatures: tabularFigures,
                              ),
                            ),
                    ),
                  ),
                ),
                IconButton.filledTonal(
                  tooltip: '下一頁',
                  onPressed: loading || page >= pages ? null : onNext,
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
          const SizedBox(height: NiuSpacing.xs),
          Text(
            total == 0 ? '' : '第 $first–$last 封，共 $total 封',
            style: theme.textTheme.labelMedium?.copyWith(
              fontFeatures: tabularFigures,
            ),
          ),
        ],
      ),
    );
  }
}

/// Asks for a page number; owns its field so closing never outlives it.
class MailPageDialog extends StatefulWidget {
  const MailPageDialog({super.key, required this.page, required this.pages});
  final int page, pages;
  @override
  State<MailPageDialog> createState() => _MailPageDialogState();
}

class _MailPageDialogState extends State<MailPageDialog> {
  late final field = TextEditingController(text: '${widget.page}');

  @override
  void dispose() {
    field.dispose();
    super.dispose();
  }

  void submit() => Navigator.pop(context, int.tryParse(field.text.trim()));

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('跳到第幾頁'),
    content: TextField(
      controller: field,
      autofocus: true,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(helperText: '共 ${widget.pages} 頁'),
      onSubmitted: (_) => submit(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: submit, child: const Text('前往')),
    ],
  );
}
