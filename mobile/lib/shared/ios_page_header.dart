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
      minimumSize: const Size(50, 50),
      backgroundColor: NiuColors.of(context).accentSoft,
      foregroundColor: NiuColors.of(context).accent,
    ),
    icon: Icon(icon, size: 21),
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
  Size get preferredSize => const Size.fromHeight(76);
  @override
  Widget build(BuildContext context) {
    final largeText = MediaQuery.textScalerOf(context).scale(26) > 34;
    final expanded = largeText || title.length > 8;
    final titleWidget = Text(
      title,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.headlineSmall,
    );
    return AppBar(
      toolbarHeight: 76,
      leadingWidth: 70,
      leading: Padding(
        padding: const EdgeInsets.only(left: 16, top: 13, bottom: 13),
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
