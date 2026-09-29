import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/shared/shared.dart';

void main() {
  test(
    'light surfaces have distinct roles rather than generated M3 near-white',
    () {
      final c = NiuColors.light;
      final t = NiuTheme.light;
      expect(c.pageBackground, isNot(c.cardSurface));
      expect(
        c.cardSurface.computeLuminance() - c.pageBackground.computeLuminance(),
        greaterThan(.1),
      );
      expect(c.surfaceSecondary, isNot(c.pageBackground));
      expect(c.surfaceTertiary, isNot(c.surfaceSecondary));
      expect(t.cardTheme.color, c.cardSurface);
      expect(t.scaffoldBackgroundColor, c.pageBackground);
      expect(t.colorScheme.surfaceContainerLow, c.surfaceSecondary);
      expect(c.navigationSurface, c.cardSurface);
    },
  );
  test('dark palette keeps OLED and existing card tone', () {
    expect(NiuColors.dark.pageBackground, Colors.black);
    expect(NiuColors.dark.cardSurface, const Color(0xff1c1c1e));
    expect(NiuColors.dark.navigationSurface, const Color(0xff1c1c1e));
    expect(NiuColors.dark.surfaceTertiary, const Color(0xff242426));
    expect(
      NiuColors.light.lerp(NiuColors.dark, 1).surfaceSecondary,
      NiuColors.dark.surfaceSecondary,
    );
  });
}
