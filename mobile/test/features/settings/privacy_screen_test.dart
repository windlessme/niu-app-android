import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/features/settings/privacy_screen.dart';
import 'package:niu_mobile/shared/shared.dart';

void main() {
  testWidgets('privacy points to the shared policy and contact address', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: NiuTheme.light, home: const PrivacyScreen()),
    );
    expect(PrivacyScreen.policy.toString(), 'https://niu-life.app/privacy');
    expect(
      PrivacyScreen.sections.any((s) => s.$3.contains('hi@niu-life.app')),
      isTrue,
    );
    expect(
      PrivacyScreen.sections.any((s) => s.$3.contains('windless.me')),
      isFalse,
    );
    await tester.scrollUntilVisible(find.text('完整隱私權政策'), 300);
    expect(find.text('完整隱私權政策'), findsOneWidget);
  });
}
