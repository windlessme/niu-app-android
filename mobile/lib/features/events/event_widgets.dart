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
        ? NiuStatusTone.neutral
        : waiting
        ? NiuStatusTone.warning
        : positive
        ? NiuStatusTone.success
        : NiuStatusTone.neutral;
    return Semantics(
      label: '活動狀態：${text.isEmpty ? '尚未提供' : text}',
      excludeSemantics: true,
      child: NiuStatusChip(label: text.isEmpty ? '-' : text, tone: tone),
    );
  }
}

class EventListCard extends StatelessWidget {
  const EventListCard({super.key, required this.event, required this.onTap});
  final CampusEvent event;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => AppCard(
    padding: const EdgeInsets.all(NiuSpacing.lg),
    onTap: onTap,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          event.name.isEmpty ? '-' : event.name,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 10),
        EventStatusPill(status: event.status),
        for (final fact in [
          (Icons.schedule, '時間', event.time),
          (Icons.place_outlined, '地點', event.location),
          (Icons.groups_outlined, '主辦單位', event.department),
          (Icons.verified_outlined, '認證時數', event.hours),
        ])
          if (fact.$3.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    fact.$1,
                    size: 20,
                    color: NiuColors.of(context).secondary,
                  ),
                  const SizedBox(width: NiuSpacing.sm),
                  Expanded(
                    child: Text(
                      '${fact.$2}：${fact.$3}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
      ],
    ),
  );
}

class EventFactGroup extends StatelessWidget {
  const EventFactGroup({super.key, required this.facts});
  final List<(String, String)> facts;
  @override
  Widget build(BuildContext context) => CompactCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < facts.length; index++) ...[
          if (index > 0)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: NiuSpacing.md),
              child: Divider(height: 1),
            ),
          Text(
            facts[index].$1,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: NiuColors.of(context).secondary,
            ),
          ),
          const SizedBox(height: NiuSpacing.xs),
          SelectableText(
            facts[index].$2.trim().isEmpty ? '-' : facts[index].$2,
          ),
        ],
      ],
    ),
  );
}
