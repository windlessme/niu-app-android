import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:niu_mobile/shared/shared.dart';
import 'package:niu_mobile/features/schedule/schedule_screen.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('schedule light/dark semantic surfaces on Android', (
    tester,
  ) async {
    final schedule = ClassSchedule.fromRows([
      ['節次', '時間', '星期二'],
      ['第二節', '09:10~10:00', '測試教師\n計算機概論\n教302'],
      ['第三節', '10:10~11:00', '測試教師\n英文一\n綜202'],
    ]);
    for (final dark in [false, true]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: dark ? NiuTheme.dark : NiuTheme.light,
          home: Scaffold(
            appBar: const NiuAppBar(title: '我的課表'),
            body: ScheduleView(schedule: schedule, initialWeekday: 2),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('計算機概論'), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (!dark) await binding.convertFlutterSurfaceToImage();
      await tester.pump();
      final bytes = await binding.takeScreenshot(
        dark ? 'surface-dark' : 'surface-light',
      );
      final dir = await getApplicationSupportDirectory();
      await File(
        '${dir.path}/surface-${dark ? 'dark' : 'light'}.png',
      ).writeAsBytes(bytes);
    }
  });
}
