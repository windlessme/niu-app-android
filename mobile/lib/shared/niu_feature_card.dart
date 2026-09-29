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
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: NiuColors.of(context).accentSoft,
            shape: BoxShape.circle,
          ),
          child: Padding(
            padding: const EdgeInsets.all(NiuSpacing.compact),
            child: Icon(icon, color: NiuColors.of(context).accent, size: 24),
          ),
        ),
        const SizedBox(height: NiuSpacing.content),
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: NiuSpacing.xs),
        Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );
}
