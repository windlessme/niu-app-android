import 'package:flutter/material.dart';
import 'niu_colors.dart';
import 'niu_icons.dart';

/// A single content surface. Cards never nest; use [NiuWell] inside a card.
class NiuCard extends StatelessWidget {
  const NiuCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(NiuSpacing.lg),
    this.onTap,
    this.color,
    this.radius = NiuRadius.card,
    this.semanticLabel,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final double radius;
  final String? semanticLabel;
  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(radius);
    Widget card = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: shape,
        boxShadow: NiuShadow.card(context),
      ),
      child: Material(
        color: color ?? NiuColors.of(context).surface,
        borderRadius: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
    if (semanticLabel != null) {
      card = Semantics(
        button: onTap != null,
        label: semanticLabel,
        excludeSemantics: true,
        onTap: onTap,
        child: card,
      );
    }
    return card;
  }
}

/// Recessed area inside a card (stats, code blocks, secondary details).
class NiuWell extends StatelessWidget {
  const NiuWell({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(NiuSpacing.md),
    this.color,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: color ?? NiuColors.of(context).fill,
      borderRadius: BorderRadius.circular(NiuRadius.lg),
    ),
    child: Padding(padding: padding, child: child),
  );
}

/// Section heading with an optional trailing action; content follows below.
class NiuSection extends StatelessWidget {
  const NiuSection({
    super.key,
    required this.title,
    this.subtitle,
    this.action,
    this.child,
    this.first = false,
  });
  final String title;
  final String? subtitle;
  final Widget? action;
  final Widget? child;

  /// Drops the top margin for the first section on a page.
  final bool first;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(top: first ? 0 : NiuSpacing.section),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(
              left: NiuSpacing.xs,
              bottom: NiuSpacing.md,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(title, style: theme.textTheme.titleLarge),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(subtitle!, style: theme.textTheme.bodySmall),
                      ],
                    ],
                  ),
                ),
                ?action,
              ],
            ),
          ),
          ?child,
        ],
      ),
    );
  }
}

/// Small uppercase-style eyebrow used above grouped rows.
class NiuEyebrow extends StatelessWidget {
  const NiuEyebrow(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      NiuSpacing.lg,
      NiuSpacing.xxl,
      NiuSpacing.lg,
      NiuSpacing.sm,
    ),
    child: Semantics(
      header: true,
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
    ),
  );
}

/// Grouped list: rows share one surface and are separated by inset hairlines.
class NiuGroup extends StatelessWidget {
  const NiuGroup({super.key, required this.children, this.insetDividers = 68});
  final List<Widget> children;

  /// Left inset of dividers so they align with row text, not icons.
  final double insetDividers;
  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        rows.add(Divider(height: 1, indent: insetDividers));
      }
      rows.add(children[i]);
    }
    return NiuCard(
      padding: EdgeInsets.zero,
      child: Column(mainAxisSize: MainAxisSize.min, children: rows),
    );
  }
}

/// Rounded square icon badge tinted by feature hue.
class NiuIconTile extends StatelessWidget {
  const NiuIconTile({
    super.key,
    required this.icon,
    this.hue = NiuHue.blue,
    this.size = NiuSize.iconTile,
  });
  final IconData icon;
  final NiuHue hue;
  final double size;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: hue.background(context),
        borderRadius: BorderRadius.circular(size * .3),
      ),
      child: Icon(icon, size: size * .52, color: hue.foreground(context)),
    ),
  );
}

/// List row with optional icon tile, supporting text, value and chevron.
class NiuRow extends StatelessWidget {
  const NiuRow({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.hue = NiuHue.blue,
    this.leading,
    this.trailing,
    this.value,
    this.onTap,
    this.chevron,
    this.destructive = false,
    this.maxSubtitleLines = 2,
  });
  final String title;
  final String? subtitle;
  final IconData? icon;
  final NiuHue hue;
  final Widget? leading;
  final Widget? trailing;

  /// Right-aligned secondary value (e.g. current setting).
  final String? value;
  final VoidCallback? onTap;

  /// Defaults to showing when the row navigates.
  final bool? chevron;
  final bool destructive;
  final int maxSubtitleLines;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = NiuColors.of(context);
    final lead =
        leading ?? (icon == null ? null : NiuIconTile(icon: icon!, hue: hue));
    return Semantics(
      button: onTap != null,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: NiuSpacing.lg,
              vertical: NiuSpacing.md,
            ),
            child: Row(
              children: [
                if (lead != null) ...[lead, const SizedBox(width: 14)],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: destructive ? colors.error : null,
                        ),
                      ),
                      if (subtitle != null && subtitle!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          maxLines: maxSubtitleLines,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
                if (value != null) ...[
                  const SizedBox(width: NiuSpacing.sm),
                  Flexible(
                    child: Text(
                      value!,
                      textAlign: TextAlign.end,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.inkSecondary,
                      ),
                    ),
                  ),
                ],
                if (trailing != null) ...[
                  const SizedBox(width: NiuSpacing.sm),
                  trailing!,
                ],
                if (chevron ?? (onTap != null && trailing == null)) ...[
                  const SizedBox(width: NiuSpacing.xs),
                  Icon(NiuIcons.forward, size: 22, color: colors.inkTertiary),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
