import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/core/session/campus_session.dart';
import 'package:niu_mobile/features/moodle/moodle_course_screen.dart';
import 'package:niu_mobile/features/moodle/moodle_demo.dart';
import 'package:niu_mobile/features/moodle/moodle_question_screen.dart';
import 'package:niu_mobile/features/moodle/moodle_questions.dart';
import 'package:niu_mobile/shared/shared.dart';

import '../../support/fakes.dart';

void main() {
  test('activities open by their canonical entry, only when available', () {
    expect(
      MoodleQuestionKind.entry({'id': 7, 'modname': 'quiz'}),
      Uri.parse('https://euni.niu.edu.tw/mod/quiz/view.php?id=7'),
    );
    expect(MoodleQuestionKind.entry({'id': 7, 'modname': 'assign'}), isNull);
    expect(
      MoodleQuestionKind.entry({'id': 7, 'modname': 'quiz', 'visible': 0}),
      isNull,
    );
    expect(
      MoodleQuestionKind.entry({
        'id': 7,
        'modname': 'choice',
        'availabilityinfo': '完成作業一後開放',
      }),
      isNull,
    );
    final sections = moodleQuestionSections([
      {
        'name': '第 1 週',
        'modules': [
          {'id': 1, 'modname': 'quiz'},
          {'id': 2, 'modname': 'resource'},
        ],
      },
      {
        'name': '第 2 週',
        'modules': [
          {'id': 1, 'modname': 'quiz'}, // Listed once only.
        ],
      },
      {
        'name': '隱藏',
        'visible': 0,
        'modules': [
          {'id': 3, 'modname': 'feedback'},
        ],
      },
    ]);
    expect(sections.single.name, '第 1 週');
    expect(sections.single.modules.single['id'], 1);
  });

  testWidgets('a quiz is started, answered and reviewed in the app', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 1600);
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
    await tester.tap(find.text('問答'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('隨堂小考'));
    await tester.pumpAndSettle();
    expect(find.byType(MoodleQuestionScreen), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.textContaining('本測驗共 2 題'), findsOneWidget);
    await tester.tap(find.text('開始作答'));
    await tester.pumpAndSettle();
    // Nothing is sent before the student confirms.
    expect(find.text('確認操作'), findsOneWidget);
    await tester.tap(find.text('確定'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    await tester.tap(find.text('後進先出（LIFO）'));
    await tester.tap(find.text('陣列'));
    await tester.tap(find.text('鏈結串列'));
    await tester.pump();
    await tester.tap(find.text('結束作答並送出'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('確定'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.text('最後成績'), findsOneWidget);
    expect(find.text('10.00 / 10.00', findRichText: true), findsOneWidget);
    expect(find.text('題目複習'), findsOneWidget);
    expect(find.text('正確'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
