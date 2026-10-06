import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../shared/shared.dart';
import 'event_models.dart';

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
  const EventListCard({
    super.key,
    required this.event,
    required this.onTap,
    this.favorite,
    this.onFavorite,
    this.selected,
  });
  final CampusEvent event;
  final VoidCallback onTap;

  /// Starred on this device; null hides the star.
  final bool? favorite;
  final VoidCallback? onFavorite;

  /// In selection mode, whether the card is chosen; null outside it.
  final bool? selected;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = NiuColors.of(context);
    return NiuCard(
      onTap: onTap,
      semanticLabel: selected == null
          ? null
          : '${selected! ? '已選取' : '未選取'}，${event.name}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (selected != null)
                Padding(
                  padding: const EdgeInsets.only(right: NiuSpacing.sm),
                  child: Icon(
                    selected!
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color: selected! ? colors.accent : colors.inkTertiary,
                  ),
                ),
              Expanded(
                child: Text(
                  event.name.isEmpty ? '-' : event.name,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              const SizedBox(width: NiuSpacing.sm),
              EventStatusPill(status: event.status),
              if (favorite != null)
                SizedBox.square(
                  dimension: 32,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    iconSize: 22,
                    tooltip: favorite! ? '取消收藏' : '加入收藏',
                    onPressed: onFavorite,
                    icon: Icon(
                      favorite!
                          ? Icons.star_rounded
                          : Icons.star_border_rounded,
                      color: favorite! ? colors.warning : colors.inkTertiary,
                    ),
                  ),
                ),
            ],
          ),
          if (event.id.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '編號 ${event.id}',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colors.inkTertiary,
                  fontFeatures: tabularFigures,
                ),
              ),
            ),
          const SizedBox(height: NiuSpacing.sm),
          for (final fact in [
            (Icons.apartment_rounded, event.department),
            (NiuIcons.time, event.time),
            (NiuIcons.location, event.location),
            (NiuIcons.person, event.people),
            (Icons.check_rounded, event.credits.map((c) => c.label).join('、')),
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
        ],
      ),
    );
  }
}

/// The school's event number; tap to copy.
class EventNumberChip extends StatelessWidget {
  const EventNumberChip({super.key, required this.id});
  final String id;
  @override
  Widget build(BuildContext context) => Tooltip(
    message: '複製活動編號',
    child: ActionChip(
      avatar: const Icon(NiuIcons.copy, size: 16),
      label: Text(
        '編號 $id',
        style: const TextStyle(fontFeatures: tabularFigures),
      ),
      onPressed: () async {
        await Clipboard.setData(ClipboardData(text: id));
        if (context.mounted) showNiuMessage(context, '已複製活動編號');
      },
    ),
  );
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
