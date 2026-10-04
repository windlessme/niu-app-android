import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/shared/niu_theme.dart';
import 'package:niu_mobile/features/home/home_screen.dart';

double contrast(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return ((x > y ? x : y) + .05) / ((x < y ? x : y) + .05);
}

void main() {
  test('dark palette retains readable text and distinct layers', () {
    final theme = NiuTheme.dark;
    final scheme = theme.colorScheme;
    expect(contrast(scheme.onSurface, scheme.surface), greaterThan(7));
    expect(contrast(scheme.onSurfaceVariant, scheme.surface), greaterThan(4.5));
    expect(contrast(scheme.onPrimary, scheme.primary), greaterThan(4.5));
    expect(theme.scaffoldBackgroundColor, isNot(scheme.surface));
  });
  testWidgets('dark home renders enlarged text without layout failure', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: NiuTheme.dark,
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
          child: const CampusHomeScreen(name: '測試同學'),
        ),
      ),
    );
    expect(find.text('今天'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
