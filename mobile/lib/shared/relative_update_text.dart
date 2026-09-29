import 'package:flutter/material.dart';

String formatRelativeUpdate(DateTime? updatedAt, {DateTime? now}) {
  if (updatedAt == null) return '尚未更新';
  final instant = now ?? DateTime.now();
  final age = instant.difference(updatedAt);
  if (age.inMinutes < 1) return '剛剛更新';
  if (age.inHours < 1) return '${age.inMinutes} 分鐘前更新';
  final date = updatedAt.toUtc().add(const Duration(hours: 8));
  final today = instant.toUtc().add(const Duration(hours: 8));
  final days = DateTime.utc(
    today.year,
    today.month,
    today.day,
  ).difference(DateTime.utc(date.year, date.month, date.day)).inDays;
  if (days == 0) {
    return '今天 ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')} 更新';
  }
  if (days == 1) return '昨天更新';
  return '$days 天前更新';
}

class RelativeUpdateText extends StatelessWidget {
  const RelativeUpdateText({super.key, required this.updatedAt, this.now});
  final DateTime? updatedAt;
  final DateTime? now;
  @override
  Widget build(BuildContext context) => Text(
    formatRelativeUpdate(updatedAt, now: now),
    style: Theme.of(context).textTheme.bodySmall,
  );
}
