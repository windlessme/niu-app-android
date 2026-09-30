import 'package:flutter/material.dart';
import '../../shared/shared.dart';
import 'events_screen.dart';

/// Status text always comes from the school; missing values are never capacity.
class EventStatusPill extends StatelessWidget {
  const EventStatusPill({super.key, required this.status});
  final String status;
  @override
  Widget build(BuildContext context) {
    final text = status.trim();
    final closed =
        text.contains('截止') || text.contains('結束') || text.contains('取消');
    final waiting =
        text.contains('額滿') || text.contains('候補') || text.contains('未開始');
    final positive =
        text.contains('報名成功') || text.contains('報名中') || text.contains('已報名');
    final tone = closed
        ? NiuTone.neutral
        : waiting
        ? NiuTone.warning
        : positive
        ? NiuTone.success
        : NiuTone.neutral;
    return Semantics(
      label: '活動狀態：${text.isEmpty ? '尚未提供' : text}',
      excludeSemantics: true,
      child: NiuBadge(label: text.isEmpty ? '-' : text, tone: tone),
    );
  }
}

class EventListCard extends StatelessWidget {
  const EventListCard({super.key, required this.event, required this.onTap});
  final CampusEvent event;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = NiuColors.of(context);
    return NiuCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  event.name.isEmpty ? '-' : event.name,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              const SizedBox(width: NiuSpacing.sm),
              EventStatusPill(status: event.status),
            ],
          ),
          const SizedBox(height: NiuSpacing.sm),
          for (final fact in [
            (NiuIcons.time, event.time),
            (NiuIcons.location, event.location),
            (Icons.apartment_rounded, event.department),
          ])
            if (fact.$2.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Icon(fact.$1, size: 16, color: colors.inkTertiary),
                    ),
                    const SizedBox(width: NiuSpacing.sm),
                    Expanded(
                      child: Text(fact.$2, style: theme.textTheme.bodySmall),
                    ),
                  ],
                ),
              ),
          if (event.hours.trim().isNotEmpty) ...[
            const SizedBox(height: NiuSpacing.sm),
            NiuTag(label: '認證 ${event.hours}', icon: Icons.verified_outlined),
          ],
        ],
      ),
    );
  }
}

class EventFactGroup extends StatelessWidget {
  const EventFactGroup({super.key, required this.facts});
  final List<(String, String)> facts;
  @override
  Widget build(BuildContext context) => NiuCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < facts.length; index++) ...[
          if (index > 0) const Divider(),
          NiuField(
            label: facts[index].$1,
            value: facts[index].$2.trim().isEmpty ? '-' : facts[index].$2,
          ),
        ],
      ],
    ),
  );
}
