import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/core/analytics/app_analytics.dart';
import 'package:niu_mobile/features/settings/settings_screen.dart';
import 'package:niu_mobile/shared/shared.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('screens are named by route path, never by page content', () {
    String? name(String? path) => AnalyticsRouteObserver.screenFor(
      MaterialPageRoute<void>(
        settings: RouteSettings(name: path),
        builder: (_) => const SizedBox(),
      ),
    );
    expect(name('/'), 'home');
    expect(name('/grades'), 'grades');
    expect(name('/library/spaces'), 'library_spaces');
    expect(name('/mail?folder=INBOX'), 'mail');
    // Unnamed routes (details pushed with a title) are not reported.
    expect(name(null), isNull);
    expect(name('期中考試時間公告'), isNull);
  });

  test('the switch is on by default and remembers being turned off', () async {
    SharedPreferences.setMockInitialValues({});
    final analytics = AppAnalytics.instance;
    await analytics.start();
    expect(analytics.enabled.value, isTrue);
    await analytics.setEnabled(false);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(AppAnalytics.preferenceKey), isFalse);
    await analytics.start();
    expect(analytics.enabled.value, isFalse);
    await analytics.setEnabled(true);
  });

  testWidgets('settings offer the analytics switch', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await AppAnalytics.instance.start();
    await tester.pumpWidget(
      MaterialApp(theme: NiuTheme.light, home: const SettingsScreen()),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('分享匿名使用統計'), 200);
    final toggle = find.descendant(
      of: find.widgetWithText(NiuRow, '分享匿名使用統計'),
      matching: find.byType(Switch),
    );
    expect(tester.widget<Switch>(toggle).value, isTrue);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(AppAnalytics.instance.enabled.value, isFalse);
    // The whole row toggles too.
    await tester.tap(find.text('分享匿名使用統計'));
    await tester.pumpAndSettle();
    expect(AppAnalytics.instance.enabled.value, isTrue);
    await AppAnalytics.instance.setEnabled(true);
  });
}
