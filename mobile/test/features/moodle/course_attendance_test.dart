import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/core/session/campus_session.dart';
import 'package:niu_mobile/features/attendance/attendance_screen.dart';
import 'package:niu_mobile/features/moodle/moodle_course_screen.dart';
import 'package:niu_mobile/features/moodle/moodle_demo.dart';
import 'package:niu_mobile/shared/shared.dart';

import '../../support/fakes.dart';

void main() {
  testWidgets('the course 出缺席 page lists sessions inside its own scroll', (
    tester,
  ) async {
    // The records once built their own ListView inside the page's list,
    // which has no height to give it: release builds drew a black page.
    tester.view.physicalSize = const Size(400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final session = CampusSession(vault: MemoryVault(), platformCleanup: []);
    addTearDown(session.dispose);
    await session.enterDemo();
    final repository = DemoMoodleRepository()..bindSession(session);
    final course = (await repository.courses()).first;
    await tester.pumpWidget(
      MaterialApp(
        theme: NiuTheme.light,
        home: MoodleCourseScreen(repository: repository, course: course),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('出缺席'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('出缺席'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('出缺席'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(AttendanceSectionList), findsOneWidget);
    expect(find.text('掃描點名'), findsOneWidget);
    expect(find.text('出席紀錄'), findsWidgets);
    expect(find.text('在學校網頁查看完整紀錄'), findsOneWidget);
  });
}
