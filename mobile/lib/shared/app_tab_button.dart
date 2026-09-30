import 'package:flutter/material.dart';
import 'niu_colors.dart';

/// Content-sized tab; the parent owns selection and horizontal scrolling.
class AppTabButton extends StatelessWidget {
  const AppTabButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onPressed,
    this.icon,
  });
  final String label;
  final bool selected;
  final VoidCallback? onPressed;
  final IconData? icon;
  @override
  Widget build(BuildContext context) {
    final colors = NiuColors.of(context);
    return Semantics(
      selected: selected,
      child: TextButton(
        style: TextButton.styleFrom(
          foregroundColor: selected ? colors.accent : colors.secondary,
          backgroundColor: selected
              ? colors.accentSoft
              : colors.surfaceSecondary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(NiuRadius.control),
          ),
        ),
        onPressed: onPressed,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: NiuSize.tabIcon),
              const SizedBox(height: NiuSpacing.xs),
            ],
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: selected ? colors.accent : colors.secondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
