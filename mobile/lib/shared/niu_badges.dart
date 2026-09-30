import 'package:flutter/material.dart';
import 'niu_colors.dart';
import 'niu_states.dart';

/// Compact status pill: tinted background, coloured label, optional icon.
class NiuBadge extends StatelessWidget {
  const NiuBadge({
    super.key,
    required this.label,
    this.tone = NiuTone.neutral,
    this.icon,
    this.solid = false,
  });
  final String label;
  final NiuTone tone;
  final IconData? icon;

  /// Filled accent style for the single most important status on a card.
  final bool solid;
  @override
  Widget build(BuildContext context) {
    final colors = NiuColors.of(context);
    final fg = solid ? colors.onAccent : tone.foreground(context);
    final bg = solid ? tone.foreground(context) : tone.background(context);
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(NiuRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: fg),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Neutral metadata tag (department, semester, credits).
class NiuTag extends StatelessWidget {
  const NiuTag({super.key, required this.label, this.icon});
  final String label;
  final IconData? icon;
  @override
  Widget build(BuildContext context) {
    final colors = NiuColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: colors.fill,
        borderRadius: BorderRadius.circular(NiuRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: colors.inkSecondary),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(label, style: Theme.of(context).textTheme.labelMedium),
          ),
        ],
      ),
    );
  }
}

/// Selectable filter pill with a 48dp touch target.
class NiuFilterChip extends StatelessWidget {
  const NiuFilterChip({
    super.key,
    required this.label,
    required this.selected,
    this.onSelected,
  });
  final String label;
  final bool selected;
  final ValueChanged<bool>? onSelected;
  @override
  Widget build(BuildContext context) {
    final colors = NiuColors.of(context);
    return Semantics(
      selected: selected,
      enabled: onSelected != null,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
        child: FilterChip(
          label: Text(label),
          selected: selected,
          onSelected: onSelected,
          showCheckmark: false,
          selectedColor: colors.ink,
          backgroundColor: colors.fill,
          labelStyle: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: selected ? colors.canvas : colors.inkSecondary,
          ),
          shape: const StadiumBorder(),
          materialTapTargetSize: MaterialTapTargetSize.padded,
        ),
      ),
    );
  }
}

/// Horizontally scrolling set of single-choice filter pills.
class NiuFilterBar<T> extends StatelessWidget {
  const NiuFilterBar({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.padding = EdgeInsets.zero,
  });
  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: padding,
    child: Row(
      children: [
        for (final (i, option) in options.indexed)
          Padding(
            padding: EdgeInsets.only(left: i == 0 ? 0 : NiuSpacing.sm),
            child: NiuFilterChip(
              label: option.$2,
              selected: option.$1 == value,
              onSelected: (_) => onChanged(option.$1),
            ),
          ),
      ],
    ),
  );
}
