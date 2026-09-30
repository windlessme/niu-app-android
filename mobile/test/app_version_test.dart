import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/core/platform/app_version.dart';
import 'package:niu_mobile/features/settings/settings_screen.dart';
import 'package:niu_mobile/shared/shared.dart';

void main() {
  testWidgets('settings shows the installed version from Android', (
    tester,
  ) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      AppVersion.channel,
      (call) async =>
          call.method == 'version' ? {'name': '1.2.3', 'build': '45'} : null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        AppVersion.channel,
        null,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(theme: NiuTheme.light, home: const SettingsScreen()),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('版本'), 200);
    expect(find.text('1.2.3（45）'), findsOneWidget);
  });
}
