import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/shared/shared.dart';

void main() {
  test('light canvas, cards and wells are distinct layers', () {
    final c = NiuColors.light;
    final t = NiuTheme.light;
    expect(c.canvas, isNot(c.surface));
    expect(
      c.surface.computeLuminance() - c.canvas.computeLuminance(),
      greaterThan(.08),
    );
    expect(t.cardTheme.color, c.surface);
    expect(t.scaffoldBackgroundColor, c.canvas);
    expect(t.navigationBarTheme.backgroundColor, c.surface);
    expect(Color.alphaBlend(c.fill, c.surface), isNot(c.surface));
  });
  test('dark palette keeps OLED canvas with raised cards', () {
    final c = NiuColors.dark;
    expect(c.canvas, Colors.black);
    expect(
      c.surface.computeLuminance(),
      greaterThan(c.canvas.computeLuminance()),
    );
    expect(
      c.raised.computeLuminance(),
      greaterThan(c.surface.computeLuminance()),
    );
    expect(NiuColors.light.lerp(NiuColors.dark, 1).surface, c.surface);
  });
}
