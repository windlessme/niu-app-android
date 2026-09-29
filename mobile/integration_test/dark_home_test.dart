import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:niu_mobile/shared/niu_theme.dart';
import 'package:niu_mobile/features/home/home_screen.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('dark home readable layers render on Android', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: NiuTheme.dark,
        home: const CampusHomeScreen(
          name: '測試同學',
          department: '資訊工程學系',
          courses: [
            HomeCourse(
              name: '資料結構',
              time: '08:10–09:00',
              room: '資101',
              current: true,
            ),
            HomeCourse(name: '微積分', time: '09:10–10:00', room: '教202'),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('資料結構'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await binding.convertFlutterSurfaceToImage();
    await tester.pump();
    await binding.takeScreenshot('dark-home');
  });
}
