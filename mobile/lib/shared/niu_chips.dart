import 'package:flutter/material.dart';
import 'niu_colors.dart';
import 'niu_icons.dart';

enum NiuStatusTone { neutral, info, success, warning, error }

class NiuStatusChip extends StatelessWidget {
  const NiuStatusChip({
    super.key,
    required this.label,
    this.tone = NiuStatusTone.neutral,
  });
  final String label;
  final NiuStatusTone tone;
  @override
  Widget build(BuildContext context) {
    final palette = NiuColors.of(context);
    final (color, icon) = switch (tone) {
      NiuStatusTone.neutral => (palette.secondaryLabel, NiuIcons.neutral),
      NiuStatusTone.info => (palette.info, NiuIcons.info),
      NiuStatusTone.success => (palette.success, NiuIcons.success),
      NiuStatusTone.warning => (palette.warning, NiuIcons.warning),
      NiuStatusTone.error => (palette.error, NiuIcons.error),
    };
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.surfaceSecondary,
          borderRadius: BorderRadius.circular(NiuRadius.pill),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: NiuSpacing.md,
            vertical: NiuSpacing.xs,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: NiuSpacing.xs),
              Flexible(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class NiuInfoChip extends StatelessWidget {
  const NiuInfoChip({super.key, required this.label, this.icon});
  final String label;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: NiuColors.of(context).tertiaryFill,
      borderRadius: BorderRadius.circular(NiuRadius.pill),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: NiuSpacing.md,
        vertical: NiuSpacing.xs,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: NiuColors.of(context).secondaryLabel),
            const SizedBox(width: NiuSpacing.xs),
          ],
          Flexible(
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: NiuColors.of(context).secondaryLabel,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

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
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    enabled: onSelected != null,
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: onSelected,
        selectedColor: NiuColors.of(context).accentSoft,
        backgroundColor: NiuColors.of(context).tertiaryFill,
        shape: const StadiumBorder(),
        showCheckmark: true,
        materialTapTargetSize: MaterialTapTargetSize.padded,
      ),
    ),
  );
}
