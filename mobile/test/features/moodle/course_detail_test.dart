import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/core/network/school_clients.dart';
import 'package:niu_mobile/features/moodle/course_detail_presentation.dart';
import 'package:niu_mobile/features/moodle/course_presentation.dart';
import 'package:niu_mobile/features/moodle/course_widgets.dart';
import 'package:niu_mobile/features/moodle/moodle_repository.dart';
import 'package:niu_mobile/features/moodle/moodle_module_screen.dart';
import 'package:niu_mobile/features/moodle/moodle_course_screen.dart';

class DetailRepository extends MoodleRepository {
  DetailRepository()
    : super(
        MoodleApiClient(schoolClient('https://euni.niu.edu.tw')),
        const MoodleSession(account: 'test', token: 'test', userId: 1),
      );
  int announcementLoads = 0, contentLoads = 0, assignmentLoads = 0;
  @override
  Future<List<Json>> announcements(int course) async {
    announcementLoads++;
    return List.generate(
      15,
      (i) => {
        'id': i + 1,
        'subject': '公告 $i',
        'userfullname': '王老師',
        'timemodified': 1725580800,
        'message': '請閱讀課程內容',
        'attachments': [],
      },
    );
  }

  @override
  Future<List<Json>> contents(int course) async {
    contentLoads++;
    return [
      {
        'name': '9月6日 - 9月12日',
        'modules': [
          {'id': 1, 'name': '第一週講義', 'modname': 'resource', 'contents': []},
        ],
      },
    ];
  }

  @override
  Future<List<Json>> assignments(int course) async {
    assignmentLoads++;
    return [
      {'id': 7, 'name': '閱讀作業', 'duedate': 0, 'intro': '閱讀說明'},
    ];
  }

  @override
  Future<Json> submission(int assignment) async => {
    'lastattempt': {'canedit': false},
  };
  @override
  Future<List<Json>> forums(int course) async => [];
  @override
  Future<List<Json>> grades(int course) async => [
    {'itemname': '期中成績'},
  ];
}

const course = {
  'id': 1,
  'fullname': '資料結構 (1131_CS)',
  'shortname': '1131_CS',
  'summary':
      '英文名稱：Data Structures\n教師：王老師\n學分：3\n教學目標：理解資料結構\n評分方式：期中 40%、期末 60%\n尚未分類的補充內容',
};

void main() {
  test('conservative sections keep unknown text and explicit percentages', () {
    final sections = courseDetailSections(CoursePresentation(course));
    expect(sections.map((s) => s.title), ['教學目標', '評分方式']);
    expect(sections.last.body, contains('40%'));
    expect(sections.last.body, contains('尚未分類的補充內容'));
    expect(sections.map((s) => s.body).join(), isNot(contains('教師：')));
    expect(
      courseDetailSections(
        CoursePresentation({
          'summary': {'bad': true},
          'customfields': [
            null,
            2,
            {'value': '未標示內容'},
          ],
        }),
      ).single.body,
      '未標示內容',
    );
    expect(courseDateRange('9月6日 - 9月12日'), '9 月 6 日 – 9 月 12 日');
    expect(courseDateRange('第一週'), '第一週');
    expect(submissionLabel(null), '繳交狀態未提供');
    expect(gradeValue(null), '未提供');
    expect(gradeValue('0'), '0');
    expect(
      sortCourseAssignments([
        {'id': 1},
        {'id': 2, 'duedate': 20},
        {'id': 3, 'duedate': 10},
      ]).map((v) => v['id']),
      [3, 2, 1],
    );
  });

  for (final brightness in Brightness.values) {
    testWidgets('course overview accessible at 320px scale 2 in $brightness', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = DetailRepository();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: MoodleCourseScreen(repository: repo, course: course),
        ),
      );
      await tester.pumpAndSettle();
      expect(repo.announcementLoads, 1);
      expect(find.text('資料結構'), findsOneWidget);
      expect(find.text('資料結構 (1131_CS)'), findsNothing);
      // The assignment's submission state could not be read.
      expect(find.text('1 份作業狀態未知，請到作業頁確認'), findsOneWidget);
      expect(tester.takeException(), isNull);

      Future<void> open(String part) async {
        await tester.scrollUntilVisible(
          find.text(part),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.ensureVisible(find.text(part));
        await tester.pumpAndSettle();
        await tester.tap(find.text(part));
        await tester.pumpAndSettle();
      }

      Future<void> back() async {
        await tester.tap(find.byTooltip('返回'));
        await tester.pumpAndSettle();
      }

      await open('資源');
      expect(find.text('9 月 6 日 – 9 月 12 日'), findsOneWidget);
      await tester.tap(find.text('第一週講義'));
      await tester.pumpAndSettle();
      expect(find.byType(MoodleModuleScreen), findsOneWidget);
      await back();
      await back();
      await open('作業');
      expect(find.text('繳交狀態未提供'), findsOneWidget);
      await back();
      await open('成績');
      expect(find.text('尚未公布'), findsOneWidget);
      await back();
      // Every part shares the overview's single load.
      expect(repo.announcementLoads, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('search covers the whole course', (tester) async {
    tester.view.physicalSize = const Size(400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: MoodleCourseScreen(
          repository: DetailRepository(),
          course: course,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '講義');
    await tester.pumpAndSettle();
    expect(find.text('資源（1）'), findsOneWidget);
    expect(find.text('查看全部資源（1）'), findsOneWidget);
    expect(find.text('待繳作業'), findsNothing);
    await tester.enterText(find.byType(TextField), '不存在的東西');
    await tester.pumpAndSettle();
    expect(find.text('找不到符合的結果'), findsOneWidget);
  });

  testWidgets('hero preserves malformed and unlabelled summary', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MoodleCourseInformation(
              course: CoursePresentation({
                'fullname': '課程',
                'summary': '<p>原始說明</p><p>不明欄位：仍保留</p>',
              }),
            ),
          ),
        ),
      ),
    );
    expect(find.text('原始說明\n不明欄位：仍保留'), findsOneWidget);
  });
}
