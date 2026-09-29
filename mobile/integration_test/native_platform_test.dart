import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:niu_mobile/core/platform/schedule_gateway.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native snapshot validation and cleanup cross the real channel', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('Native bridge fixture'))),
    );
    const gateway = ScheduleGateway();
    await gateway.clear();
    await gateway.saveSnapshot(
      const ScheduleSnapshot(
        semesterStart: '2026-09-01',
        semesterEnd: '2027-01-31',
        blocks: [
          ScheduleBlock(
            id: 'fixture',
            title: '測試課程',
            weekday: 1,
            startMinute: 490,
            endMinute: 540,
          ),
        ],
      ),
    );
    expect(await gateway.setReminders(enabled: false), isTrue);
    await expectLater(
      ScheduleGateway.channel.invokeMethod<void>('saveSnapshot', {
        'version': 999,
      }),
      throwsA(isA<PlatformException>()),
    );
    await gateway.clear();
  });
}
