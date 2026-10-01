import 'package:flutter/material.dart';

import '../../shared/shared.dart';
import 'mail_models.dart';

const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];

DateTime _taipei(DateTime t) => t.toUtc().add(const Duration(hours: 8));
String _two(int v) => v.toString().padLeft(2, '0');

/// 2026/10/1（週四）14:05
String formatMailDateLong(DateTime t) {
  final d = _taipei(t);
  return '${d.year}/${d.month}/${d.day}（週${_weekdays[d.weekday - 1]}）'
      '${_two(d.hour)}:${_two(d.minute)}';
}

/// List time: today's clock, this year's month/day, else the full date.
String formatMailDateShort(DateTime t, DateTime now) {
  final d = _taipei(t), n = _taipei(now);
  if (d.year == n.year && d.month == n.month && d.day == n.day) {
    return '${_two(d.hour)}:${_two(d.minute)}';
  }
  final yesterday = n.subtract(const Duration(days: 1));
  if (d.year == yesterday.year &&
      d.month == yesterday.month &&
      d.day == yesterday.day) {
    return '昨天';
  }
  return d.year == n.year
      ? '${d.month}/${d.day}'
      : '${d.year}/${d.month}/${d.day}';
}

/// Initial on a colour picked from the name, so senders stay recognisable.
class MailAvatar extends StatelessWidget {
  const MailAvatar({super.key, required this.name, this.size = 40});
  final String name;
  final double size;
  @override
  Widget build(BuildContext context) {
    final trimmed = name.trim();
    final initial = trimmed.isEmpty
        ? '?'
        : trimmed.characters.first.toUpperCase();
    final hue = NiuHue.values[trimmed.hashCode.abs() % NiuHue.values.length];
    final dark = Theme.of(context).brightness == Brightness.dark;
    final color = dark ? hue.dark : hue.light;
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withValues(alpha: dark ? 0.24 : 0.14),
          shape: BoxShape.circle,
        ),
        child: Text(
          initial,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w700,
            fontSize: size * 0.42,
          ),
        ),
      ),
    );
  }
}

IconData folderIcon(MailFolder f) => switch (f.name) {
  MailFolder.inbox => Icons.inbox_rounded,
  MailFolder.sent => Icons.send_rounded,
  MailFolder.drafts => Icons.edit_note_rounded,
  MailFolder.trash => Icons.delete_outline_rounded,
  _ => NiuIcons.folder,
};

Future<MailFolder?> pickMailFolder(
  BuildContext context,
  List<MailFolder> folders,
) => showModalBottomSheet<MailFolder>(
  context: context,
  showDragHandle: true,
  builder: (context) => SafeArea(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            NiuSpacing.gutter,
            0,
            NiuSpacing.gutter,
            NiuSpacing.sm,
          ),
          child: Text('移到', style: Theme.of(context).textTheme.titleLarge),
        ),
        for (final f in folders)
          ListTile(
            leading: Icon(folderIcon(f)),
            title: Text(f.label),
            onTap: () => Navigator.pop(context, f),
          ),
        const SizedBox(height: NiuSpacing.md),
      ],
    ),
  ),
);
