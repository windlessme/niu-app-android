import 'package:flutter/material.dart';
import 'app_cards.dart';
import 'niu_colors.dart';

class NiuFeatureCard extends StatelessWidget {
  const NiuFeatureCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });
  final String title, subtitle;
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => AppCard(
    onTap: onTap,
    padding: const EdgeInsets.all(NiuSpacing.content),
    borderRadius: NiuRadius.compact,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: NiuColors.of(context).accentSoft,
              shape: BoxShape.circle,
            ),
            child: Padding(
              padding: const EdgeInsets.all(NiuSpacing.content),
              child: Icon(icon, color: NiuColors.of(context).accent, size: 24),
            ),
          ),
        ),
        const SizedBox(height: NiuSpacing.compact),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: NiuSpacing.xs),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelMedium,
        ),
      ],
    ),
  );
}
