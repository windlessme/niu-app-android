import 'package:flutter/material.dart';
import 'niu_colors.dart';
import 'niu_motion.dart';

/// Equal-width segmented control for 2–4 peer views of the same content.
class NiuSegmented<T> extends StatelessWidget {
  const NiuSegmented({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
  });
  final List<(T, String)> segments;
  final T value;
  final ValueChanged<T>? onChanged;
  @override
  Widget build(BuildContext context) {
    final colors = NiuColors.of(context);
    final theme = Theme.of(context);
    final index = segments.indexWhere((s) => s.$1 == value);
    final minHeight = MediaQuery.textScalerOf(context).scale(15) + 26;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: colors.fill,
        borderRadius: BorderRadius.circular(NiuRadius.pill),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth / segments.length;
          final height = minHeight < 42 ? 42.0 : minHeight;
          return SizedBox(
            height: height,
            child: Stack(
              children: [
                if (index >= 0)
                  AnimatedPositioned(
                    duration: NiuMotion.duration(context),
                    curve: NiuMotion.curve,
                    left: width * index,
                    width: width,
                    top: 0,
                    bottom: 0,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? colors.fillStrong
                            : colors.surface,
                        borderRadius: BorderRadius.circular(NiuRadius.pill),
                        boxShadow: [
                          BoxShadow(
                            color: colors.shadow.withValues(
                              alpha: colors.shadow.a * 2,
                            ),
                            blurRadius: 6,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                  ),
                Row(
                  children: [
                    for (final (i, segment) in segments.indexed)
                      Expanded(
                        child: Semantics(
                          selected: i == index,
                          button: true,
                          enabled: onChanged != null,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(NiuRadius.pill),
                            onTap: onChanged == null
                                ? null
                                : () => onChanged!(segment.$1),
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                ),
                                child: Text(
                                  segment.$2,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    color: i == index
                                        ? colors.ink
                                        : colors.inkSecondary,
                                    fontWeight: i == index
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Scrollable underline tabs for sections within one detail page.
class NiuTabs extends StatelessWidget {
  const NiuTabs({
    super.key,
    required this.labels,
    required this.selected,
    required this.onChanged,
    this.padding = const EdgeInsets.symmetric(horizontal: NiuSpacing.gutter),
  });
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onChanged;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) {
    final colors = NiuColors.of(context);
    final theme = Theme.of(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: padding,
      child: Row(
        children: [
          for (final (i, label) in labels.indexed)
            Semantics(
              selected: i == selected,
              button: true,
              child: InkWell(
                borderRadius: BorderRadius.circular(NiuRadius.md),
                onTap: () => onChanged(i),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          label,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: i == selected
                                ? colors.ink
                                : colors.inkSecondary,
                            fontWeight: i == selected
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 6),
                        AnimatedContainer(
                          duration: NiuMotion.duration(context),
                          height: 3,
                          width: i == selected ? 20 : 0,
                          decoration: BoxDecoration(
                            color: colors.accent,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
