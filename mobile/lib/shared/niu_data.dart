import 'package:flutter/material.dart';
import 'niu_colors.dart';
import 'niu_motion.dart';

const tabularFigures = [FontFeature.tabularFigures()];

/// Headline metric: large value, small label, optional caption.
class NiuStat extends StatelessWidget {
  const NiuStat({
    super.key,
    required this.value,
    required this.label,
    this.unit,
    this.caption,
    this.color,
    this.large = false,
  });
  final String value;
  final String label;
  final String? unit;
  final String? caption;
  final Color? color;
  final bool large;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style =
        (large ? theme.textTheme.displaySmall : theme.textTheme.headlineSmall)
            ?.copyWith(color: color, fontFeatures: tabularFigures);
    return Semantics(
      label: '$label $value${unit ?? ''}${caption == null ? '' : '，$caption'}',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: theme.textTheme.labelMedium),
          const SizedBox(height: 4),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: value, style: style),
                if (unit != null)
                  TextSpan(
                    text: ' $unit',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
          if (caption != null) ...[
            const SizedBox(height: 2),
            Text(caption!, style: theme.textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}

/// Rounded progress track; [value] is clamped to 0–1.
class NiuProgressBar extends StatelessWidget {
  const NiuProgressBar({
    super.key,
    required this.value,
    this.color,
    this.height = 8,
    this.semanticLabel,
  });
  final double value;
  final Color? color;
  final double height;
  final String? semanticLabel;
  @override
  Widget build(BuildContext context) {
    final colors = NiuColors.of(context);
    final v = value.isNaN ? 0.0 : value.clamp(0.0, 1.0);
    return Semantics(
      label: semanticLabel,
      value: '${(v * 100).round()}%',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(NiuRadius.pill),
        child: SizedBox(
          height: height,
          child: Stack(
            children: [
              Positioned.fill(child: ColoredBox(color: colors.fill)),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: v),
                duration: NiuMotion.duration(context, NiuMotion.slow),
                curve: Curves.easeOutCubic,
                builder: (context, t, _) => FractionallySizedBox(
                  widthFactor: t,
                  heightFactor: 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: color ?? colors.accent,
                      borderRadius: BorderRadius.circular(NiuRadius.pill),
                    ),
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

/// Label above a full, selectable value. Missing values render as an em dash.
class NiuField extends StatelessWidget {
  const NiuField({
    super.key,
    required this.label,
    required this.value,
    this.selectable = true,
  });
  final String label, value;
  final bool selectable;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = value.trim().isEmpty ? '—' : value;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: NiuSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.labelMedium),
          const SizedBox(height: 3),
          selectable
              ? SelectableText(text, style: theme.textTheme.bodyLarge)
              : Text(text, style: theme.textTheme.bodyLarge),
        ],
      ),
    );
  }
}

/// Horizontal label / value pair for dense detail lists.
class NiuKeyValue extends StatelessWidget {
  const NiuKeyValue({
    super.key,
    required this.label,
    required this.value,
    this.emphasis = false,
  });
  final String label, value;
  final bool emphasis;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = value.trim().isEmpty ? '—' : value;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: NiuColors.of(context).inkSecondary,
              ),
            ),
          ),
          const SizedBox(width: NiuSpacing.md),
          Expanded(
            flex: 3,
            child: Text(
              text,
              textAlign: TextAlign.end,
              style:
                  (emphasis
                          ? theme.textTheme.titleMedium
                          : theme.textTheme.bodyMedium)
                      ?.copyWith(fontFeatures: tabularFigures),
            ),
          ),
        ],
      ),
    );
  }
}
