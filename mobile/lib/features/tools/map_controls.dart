import 'package:flutter/material.dart';

import '../../shared/shared.dart';

/// A raised capsule for controls floating over a map.
class MapFloating extends StatelessWidget {
  const MapFloating({
    super.key,
    required this.child,
    this.radius = NiuRadius.pill,
  });
  final Widget child;
  final double radius;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: NiuColors.of(context).raised,
      borderRadius: BorderRadius.circular(radius),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: .12),
          blurRadius: 12,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: Material(
      type: MaterialType.transparency,
      borderRadius: BorderRadius.circular(radius),
      clipBehavior: Clip.antiAlias,
      child: child,
    ),
  );
}
