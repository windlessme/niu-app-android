import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'dart:math' as math;
import 'niu_colors.dart';
import 'niu_icons.dart';

class CircleIconButton extends StatelessWidget {
  const CircleIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    String? tooltip,
    String? label,
  }) : assert(tooltip != null || label != null),
       tooltip = tooltip ?? label ?? '';
  final IconData icon;
  final VoidCallback? onPressed;
  final String tooltip;
  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    style: IconButton.styleFrom(
      minimumSize: const Size(NiuSize.touchTarget, NiuSize.touchTarget),
      backgroundColor: NiuColors.of(context).surfaceSecondary,
      foregroundColor: NiuColors.of(context).text,
      disabledForegroundColor: NiuColors.of(context).tertiary,
    ),
    icon: Icon(icon, size: NiuSize.toolbarIcon),
  );
}

class IosPageHeader extends StatelessWidget implements PreferredSizeWidget {
  const IosPageHeader({
    super.key,
    required this.title,
    this.actions = const [],
    this.leading,
  });
  final String title;
  final List<Widget> actions;
  final Widget? leading;
  @override
  Size get preferredSize => const Size.fromHeight(NiuSize.toolbar);
  @override
  Widget build(BuildContext context) {
    final largeText = MediaQuery.textScalerOf(context).scale(26) > 34;
    final expanded = largeText || title.length > 8;
    final titleWidget = Text(
      title,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.titleMedium,
    );
    return AppBar(
      toolbarHeight: NiuSize.toolbar,
      leadingWidth: NiuSize.touchTarget + NiuSpacing.lg,
      leading: Padding(
        padding: const EdgeInsets.only(
          left: NiuSpacing.sm,
          top: NiuSpacing.sm,
          bottom: NiuSpacing.sm,
        ),
        child:
            leading ??
            CircleIconButton(
              icon: NiuIcons.back,
              tooltip: '返回',
              onPressed: () async {
                final popped = await Navigator.of(context).maybePop();
                if (!popped && context.mounted) {
                  final router = GoRouter.maybeOf(context);
                  if (router != null) {
                    if (router.canPop()) {
                      router.pop();
                    } else {
                      router.go('/');
                    }
                  }
                }
              },
            ),
      ),
      title: LayoutBuilder(
        builder: (context, constraints) {
          // Preserve the full title in accessibility even when the visual header
          // has to fit beside several actions on a narrow display.
          return Semantics(
            header: true,
            label: title,
            child: ExcludeSemantics(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: math.max(0, constraints.maxWidth),
                ),
                child: expanded
                    ? FittedBox(fit: BoxFit.scaleDown, child: titleWidget)
                    : titleWidget,
              ),
            ),
          );
        },
      ),
      actions: [...actions, const SizedBox(width: 16)],
    );
  }
}
