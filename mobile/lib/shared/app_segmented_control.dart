import 'package:flutter/cupertino.dart';
import 'niu_colors.dart';

class AppSegmentedControl<T extends Object> extends StatelessWidget {
  const AppSegmentedControl({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
    this.segmentPadding = const EdgeInsets.symmetric(
      horizontal: 12,
      vertical: 12,
    ),
  });
  final Map<T, Widget> segments;
  final T? value;
  final ValueChanged<T>? onChanged;
  final EdgeInsetsGeometry segmentPadding;
  @override
  Widget build(BuildContext context) => CupertinoSlidingSegmentedControl<T>(
    groupValue: value,
    backgroundColor: NiuColors.of(context).surfaceSecondary,
    thumbColor: NiuColors.of(context).selectedControlSurface,
    children: segments.map(
      (key, child) => MapEntry(
        key,
        Padding(
          padding: segmentPadding,
          child: Center(child: child),
        ),
      ),
    ),
    onValueChanged: (value) {
      if (value != null) onChanged?.call(value);
    },
    disabledChildren: onChanged == null ? segments.keys.toSet() : <T>{},
  );
}
