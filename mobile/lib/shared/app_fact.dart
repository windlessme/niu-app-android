import 'package:flutter/material.dart';
import 'niu_colors.dart';

/// A field retains its full value while separating its label from the content.
class AppFact extends StatelessWidget {
  const AppFact({super.key, required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: NiuSpacing.sm),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: NiuSpacing.xs),
        SelectableText(
          value.trim().isEmpty ? '-' : value,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ],
    ),
  );
}
