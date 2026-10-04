import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/shared/shared.dart';

void main() {
  for (final (name, theme, colors) in [
    ('light', NiuTheme.light, NiuColors.light),
    ('dark', NiuTheme.dark, NiuColors.dark),
  ]) {
    test('$name: an off switch shows its track outline', () {
      final s = theme.switchTheme;
      const off = <WidgetState>{};
      const on = {WidgetState.selected};
      // Off: outlined track and grey thumb, so it reads as a switch.
      expect(s.trackOutlineColor!.resolve(off), colors.inkTertiary);
      expect(s.thumbColor!.resolve(off), colors.inkTertiary);
      expect(s.trackColor!.resolve(off), colors.fillStrong);
      // On: filled accent track, no outline.
      expect(s.trackOutlineColor!.resolve(on), Colors.transparent);
      expect(s.trackColor!.resolve(on), colors.accent);
      expect(s.thumbColor!.resolve(on), colors.onAccent);
      // Disabled off stays visible but fainter.
      final disabled = s.trackOutlineColor!.resolve({WidgetState.disabled})!;
      expect(disabled.a, lessThan(colors.inkTertiary.a));
      expect(disabled.a, greaterThan(0));
    });
  }
}
