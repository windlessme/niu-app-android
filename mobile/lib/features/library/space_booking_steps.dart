import 'package:flutter/material.dart';
import '../../core/time/campus_date.dart';
import '../../shared/shared.dart';
import 'space_booking_controller.dart';
import 'space_models.dart';

Widget spaceCaption(ThemeData theme, String text) => Padding(
  padding: const EdgeInsets.only(bottom: NiuSpacing.sm),
  child: Semantics(
    header: true,
    child: Text(text, style: theme.textTheme.labelMedium),
  ),
);

Widget spacePlaceholder(BuildContext context, String text) => ConstrainedBox(
  constraints: const BoxConstraints(minHeight: 44),
  child: Align(
    alignment: Alignment.centerLeft,
    child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
  ),
);

/// A numbered step; the accessory sits beside the heading when it fits.
class SpaceStepCard extends StatelessWidget {
  const SpaceStepCard({
    super.key,
    required this.step,
    required this.title,
    required this.child,
    this.subtitle,
    this.accessory,
  });
  final int step;
  final String title;
  final String? subtitle;
  final Widget? accessory;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = NiuColors.of(context);
    final heading = Semantics(
      header: true,
      label: ['步驟 $step', title, ?subtitle].join('，'),
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            margin: const EdgeInsets.only(top: 1),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.accent,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$step',
              style: theme.textTheme.labelMedium?.copyWith(
                color: colors.onAccent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: NiuSpacing.sm),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFeatures: tabularFigures,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    return NiuCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (accessory == null)
            heading
          else
            Row(
              children: [
                Expanded(
                  child: Align(alignment: Alignment.centerLeft, child: heading),
                ),
                accessory!,
              ],
            ),
          const SizedBox(height: NiuSpacing.md),
          child,
        ],
      ),
    );
  }
}

/// Two weeks of day buttons; further dates come from 其他日期.
class SpaceDayStrip extends StatefulWidget {
  const SpaceDayStrip({
    super.key,
    required this.today,
    required this.selected,
    required this.onSelect,
  });
  final CampusDate today, selected;
  final ValueChanged<CampusDate>? onSelect;
  @override
  State<SpaceDayStrip> createState() => _SpaceDayStripState();
}

class _SpaceDayStripState extends State<SpaceDayStrip> {
  static const _count = 14, _width = 58.0, _gap = NiuSpacing.sm;
  final scroll = ScrollController();

  @override
  void didUpdateWidget(covariant SpaceDayStrip old) {
    super.didUpdateWidget(old);
    if (old.selected != widget.selected) _reveal();
  }

  void _reveal() {
    final index = daysBetween(widget.today, widget.selected);
    if (index < 0 || index >= _count || !scroll.hasClients) return;
    final target =
        index * (_width + _gap) -
        (scroll.position.viewportDimension - _width) / 2;
    scroll.animateTo(
      target.clamp(0, scroll.position.maxScrollExtent),
      duration: NiuMotion.duration(context),
      curve: NiuMotion.curve,
    );
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = NiuColors.of(context);
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6);
    return SizedBox(
      height: 74 * scale,
      child: ListView.separated(
        controller: scroll,
        scrollDirection: Axis.horizontal,
        itemCount: _count,
        separatorBuilder: (_, _) => const SizedBox(width: _gap),
        itemBuilder: (context, i) {
          final day = addDays(widget.today, i);
          final selected = day == widget.selected;
          final relative = relativeDay(day, widget.today);
          final ink = selected
              ? colors.onAccent
              : i == 0
              ? colors.accent
              : colors.ink;
          return Semantics(
            selected: selected,
            button: true,
            label:
                '${relative == null ? '' : '$relative，'}'
                '${day.month}月${day.day}日，${shortWeekday(day)}',
            excludeSemantics: true,
            child: Material(
              color: selected ? colors.accent : colors.fill,
              borderRadius: BorderRadius.circular(NiuRadius.md),
              child: InkWell(
                borderRadius: BorderRadius.circular(NiuRadius.md),
                onTap: widget.onSelect == null
                    ? null
                    : () => widget.onSelect!(day),
                child: SizedBox(
                  width: _width * scale.clamp(1.0, 1.4),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        relative ?? shortWeekday(day),
                        style: theme.textTheme.labelSmall?.copyWith(color: ink),
                      ),
                      Text(
                        '${day.day}',
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: ink,
                          fontWeight: FontWeight.w700,
                          fontFeatures: tabularFigures,
                          height: 1.15,
                        ),
                      ),
                      Text(
                        '${day.month}月',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: ink.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Equal-width options laid out in as many columns as fit.
class SpaceOptionGrid extends StatelessWidget {
  const SpaceOptionGrid({
    super.key,
    required this.minWidth,
    required this.children,
  });
  final double minWidth;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);
      final columns = (box.maxWidth / (minWidth * scale)).floor().clamp(1, 6);
      final width = (box.maxWidth - NiuSpacing.sm * (columns - 1)) / columns;
      return Wrap(
        spacing: NiuSpacing.sm,
        runSpacing: NiuSpacing.sm,
        children: [
          for (final child in children) SizedBox(width: width, child: child),
        ],
      );
    },
  );
}

/// Selection shown by tick, outline and colour together.
class SpaceOption extends StatelessWidget {
  const SpaceOption({
    super.key,
    required this.title,
    required this.selected,
    required this.onTap,
    this.detail,
  });
  final String title;
  final String? detail;
  final bool selected;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = NiuColors.of(context);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(NiuRadius.md),
      side: BorderSide(
        color: selected ? colors.accent : Colors.transparent,
        width: 1.5,
      ),
    );
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? colors.accentSoft : colors.fill,
        shape: shape,
        child: InkWell(
          customBorder: shape,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: NiuSpacing.md,
                vertical: NiuSpacing.sm,
              ),
              child: Row(
                children: [
                  if (selected) ...[
                    Icon(Icons.check_rounded, size: 18, color: colors.accent),
                    const SizedBox(width: NiuSpacing.xs),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: selected ? colors.accent : colors.ink,
                          ),
                        ),
                        if (detail != null)
                          Text(detail!, style: theme.textTheme.labelSmall),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Step 3: start time ───────────────────────────────────────────────────────

class SpaceSlotSection extends StatelessWidget {
  const SpaceSlotSection({super.key, required this.controller});
  final SpaceBookingController controller;

  static const _periods = [
    ('上午', 0, 12 * 60),
    ('下午', 12 * 60, 18 * 60),
    ('晚上', 18 * 60, 24 * 60),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = controller;
    final rules = c.rules;
    return SpaceStepCard(
      step: 3,
      title: '選擇開始時間',
      subtitle: rules == null
          ? null
          : '開放 ${formatMinute(rules.open)}–${formatMinute(rules.close)} · 每格 30 分鐘',
      child: rules == null
          ? spacePlaceholder(
              context,
              c.loading
                  ? '正在取得可預約時段…'
                  : c.selectionMessage ?? '選好設備後，這裡會顯示當日時段。',
            )
          : _content(context, theme, rules),
    );
  }

  Widget _content(BuildContext context, ThemeData theme, SpaceRules rules) {
    final c = controller;
    final all = c.slots;
    final upcoming = [
      for (final s in all)
        if (s.state != SlotState.past) s,
    ];
    final past = [
      for (final s in all)
        if (s.state == SlotState.past) s,
    ];
    final label = c.timeLabel;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (rules.quotaExhausted) ...[
          const NiuBanner(tone: NiuTone.warning, message: '剩餘額度不足以建立新的預約。'),
          const SizedBox(height: NiuSpacing.md),
        ],
        if (upcoming.isEmpty)
          Text('這天已沒有尚未開始的時段，請選擇其他日期。', style: theme.textTheme.bodyMedium)
        else ...[
          Text(
            label != null
                ? '已選 $label，可拖曳下方滑桿調整時長；點其他時間可重新選擇。'
                : '點選開始時間，最短預約 ${formatHours(rules.minHours)} 小時。',
            style: theme.textTheme.bodySmall,
          ),
          for (final (name, from, to) in _periods)
            if (upcoming.any((s) => s.minute >= from && s.minute < to)) ...[
              const SizedBox(height: NiuSpacing.md),
              spaceCaption(theme, name),
              SpaceSlotGrid(
                slots: [
                  for (final s in upcoming)
                    if (s.minute >= from && s.minute < to) s,
                ],
                controller: c,
              ),
            ],
        ],
        if (past.isNotEmpty)
          Theme(
            data: theme.copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(
                '已開始的時段（${past.length}）',
                style: theme.textTheme.titleSmall,
              ),
              expandedAlignment: Alignment.centerLeft,
              childrenPadding: const EdgeInsets.only(bottom: NiuSpacing.sm),
              children: [
                Text(
                  past.map((s) => formatMinute(s.minute)).join('、'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFeatures: tabularFigures,
                  ),
                ),
              ],
            ),
          )
        else
          const SizedBox(height: NiuSpacing.md),
        Row(
          children: [
            Expanded(
              child: SpaceStat(
                label: '剩餘額度',
                value: '${formatHours(rules.remainingHours)} 小時',
              ),
            ),
            const SizedBox(width: NiuSpacing.sm),
            Expanded(
              child: SpaceStat(
                label: '單次可預約',
                value:
                    '${formatHours(rules.minHours)}–${formatHours(rules.maxHours)} 小時',
              ),
            ),
          ],
        ),
        Theme(
          data: theme.copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text('使用規則', style: theme.textTheme.titleSmall),
            expandedAlignment: Alignment.centerLeft,
            childrenPadding: EdgeInsets.zero,
            children: [
              Text(
                '每次 ${formatHours(rules.minHours)}–${formatHours(rules.maxHours)} 小時，'
                '以 30 分鐘調整。預約需連續且不得跨過已占用的時段，並依圖書館規定報到。',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class SpaceStat extends StatelessWidget {
  const SpaceStat({super.key, required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MergeSemantics(
      child: NiuWell(
        padding: const EdgeInsets.all(NiuSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.labelSmall),
            const SizedBox(height: 2),
            Text(
              value,
              style: theme.textTheme.titleSmall?.copyWith(
                fontFeatures: tabularFigures,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SpaceSlotGrid extends StatelessWidget {
  const SpaceSlotGrid({
    super.key,
    required this.slots,
    required this.controller,
  });
  final List<SpaceSlot> slots;
  final SpaceBookingController controller;
  @override
  Widget build(BuildContext context) => SpaceOptionGrid(
    minWidth: 72,
    children: [
      for (final s in slots)
        SpaceSlotCell(
          slot: s,
          start: controller.start == s.minute && controller.timeLabel != null,
          selected: controller.isSelected(s.minute),
          onTap: controller.busy
              ? null
              : () => controller.selectStart(s.minute),
        ),
    ],
  );
}

/// One 30-minute cell: filled when free, outlined with a reason when not.
class SpaceSlotCell extends StatelessWidget {
  const SpaceSlotCell({
    super.key,
    required this.slot,
    required this.start,
    required this.selected,
    required this.onTap,
  });
  final SpaceSlot slot;
  final bool start, selected;
  final VoidCallback? onTap;

  String get status {
    if (selected) return start ? '開始' : '已選';
    return switch (slot.state) {
      SlotState.available => '可選',
      SlotState.occupied => '已占用',
      SlotState.mine => '我的預約',
      SlotState.past => '已開始',
      SlotState.tooShort => '空檔不足',
      SlotState.quota => '額度不足',
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = NiuColors.of(context);
    final available = slot.state == SlotState.available;
    final enabled = available || selected;
    final (Color fill, Color ink, Color border) = start
        ? (colors.accent, colors.onAccent, Colors.transparent)
        : selected
        ? (
            colors.accentSoft,
            colors.accent,
            colors.accent.withValues(alpha: 0.5),
          )
        : slot.state == SlotState.mine
        ? (
            Colors.transparent,
            colors.accent,
            colors.accent.withValues(alpha: 0.5),
          )
        : available
        ? (colors.fill, colors.ink, Colors.transparent)
        : (Colors.transparent, colors.inkTertiary, colors.hairline);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(NiuRadius.sm),
      side: BorderSide(color: border),
    );
    final time = formatMinute(slot.minute);
    final spoken = slot.state == SlotState.tooShort && !selected
        ? '空檔 ${formatHours(slot.continuous / 60)} 小時，不足最短預約時長'
        : status;
    return Semantics(
      button: enabled,
      selected: selected,
      label: '$time，$spoken',
      excludeSemantics: true,
      child: Material(
        color: fill,
        shape: shape,
        child: InkWell(
          customBorder: shape,
          onTap: enabled ? onTap : null,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: NiuSpacing.xs),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    time,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: ink,
                      fontFeatures: tabularFigures,
                      decoration: slot.state == SlotState.occupied && !selected
                          ? TextDecoration.lineThrough
                          : null,
                      decorationColor: ink,
                    ),
                  ),
                  Text(
                    status,
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                    style: theme.textTheme.labelSmall?.copyWith(color: ink),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Bottom bar ───────────────────────────────────────────────────────────────
