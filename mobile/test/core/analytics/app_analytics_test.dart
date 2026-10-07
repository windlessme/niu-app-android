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

  test('on by default; an earlier opt-out is kept', () async {
    SharedPreferences.setMockInitialValues({});
    final analytics = AppAnalytics.instance;
    await analytics.start();
    expect(analytics.enabled, isTrue);
    SharedPreferences.setMockInitialValues({AppAnalytics.preferenceKey: false});
    await analytics.start();
    expect(analytics.enabled, isFalse);
    SharedPreferences.setMockInitialValues({});
    await analytics.start();
  });

  testWidgets('settings no longer offer an analytics switch', (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: NiuTheme.light, home: const SettingsScreen()),
    );
    await tester.pumpAndSettle();
    expect(find.text('分享匿名使用統計'), findsNothing);
    expect(find.text('隱私'), findsNothing);
  });
}
