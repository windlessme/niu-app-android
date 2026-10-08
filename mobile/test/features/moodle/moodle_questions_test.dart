import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/core/session/campus_session.dart';
import 'package:niu_mobile/features/moodle/moodle_course_screen.dart';
import 'package:niu_mobile/features/moodle/moodle_demo.dart';
import 'package:niu_mobile/features/moodle/moodle_question_demo.dart';
import 'package:niu_mobile/features/moodle/moodle_question_screen.dart';
import 'package:niu_mobile/features/moodle/moodle_question_widgets.dart';
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
    await tester.scrollUntilVisible(
      find.text('問答'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('問答'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('隨堂小考'));
    await tester.pumpAndSettle();
    expect(find.byType(MoodleQuestionScreen), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.textContaining('本測驗共 4 題'), findsOneWidget);
    // Quiz steps rely on Moodle's own confirmations, as on iOS.
    await tester.tap(find.text('開始作答'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('確認操作'), findsNothing);
    expect(find.text('已作答 0／4'), findsOneWidget);
    expect(find.byType(TimerChip), findsOneWidget);

    // Numbering sits in the answer mark; the bubbles follow input live.
    await tester.tap(find.text('後進先出（LIFO）'));
    await tester.tap(find.text('陣列'));
    await tester.tap(find.text('鏈結串列'));
    await tester.pump();
    expect(find.text('已作答 2／4'), findsOneWidget);
    await tester.tap(find.text('下一頁'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    // Matching stems use compact pickers; ordering moves with buttons.
    expect(find.text('將資料結構與存取方式配對。'), findsOneWidget);
    await tester.tap(find.text('選擇答案').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('先進先出'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('選擇答案'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('後進先出').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('上移「O(1)」'));
    await tester.pump();
    await tester.tap(find.byTooltip('上移「O(n)」'));
    await tester.pump();
    expect(find.text('已作答 4／4'), findsOneWidget);

    await tester.tap(find.text('檢查並交卷'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('交卷前檢查'), findsOneWidget);
    expect(find.text('全部 4 題都已作答。'), findsOneWidget);
    await tester.tap(find.text('交卷'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('一旦提交，你將不能再更改這次作答的答案。'), findsOneWidget);
    await tester.tap(find.text('全部提交並結束'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.text('最後成績'), findsOneWidget);
    expect(find.text('10.00 / 10.00', findRichText: true), findsOneWidget);
    expect(find.text('題目複習'), findsOneWidget);
    expect(find.text('正確'), findsNWidgets(4));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a timed quiz writes each change to the school form', (
    tester,
  ) async {
    final session = CampusSession(vault: MemoryVault(), platformCleanup: []);
    addTearDown(session.dispose);
    await session.enterDemo();
    final repository = DemoMoodleRepository()..bindSession(session);
    final driver = _RecordingDriver();
    await tester.pumpWidget(
      MaterialApp(
        theme: NiuTheme.light,
        home: MoodleQuestionScreen(
          repository: repository,
          module: const {'id': 9, 'modname': 'quiz', 'name': '隨堂小考'},
          driver: driver,
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('開始作答'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(driver.staged, isEmpty);
    await tester.tap(find.text('先進先出（FIFO）'));
    await tester.pumpAndSettle();
    expect(driver.staged.last['q1'], ['q1a']);
    // A jump to another page saves this one through Moodle's handler.
    await tester.tap(find.bySemanticsLabel(RegExp('^第 3 題')));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(driver.performed.last.$1, 'nav3');
    expect(driver.performed.last.$2, ['q1', 'q2']);
    expect(find.text('將資料結構與存取方式配對。'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}

class _RecordingDriver extends DemoQuestionDriver {
  final staged = <Map<String, List<String>>>[];
  final performed = <(String, List<String>)>[];
  @override
  Future<String?> stage(String revision, Map<String, List<String>> answers) {
    staged.add({...answers});
    return super.stage(revision, answers);
  }

  @override
  Future<String?> perform(
    String revision,
    String actionId,
    Map<String, List<String>> answers,
  ) {
    performed.add((actionId, answers.keys.toList()));
    return super.perform(revision, actionId, answers);
  }
}
