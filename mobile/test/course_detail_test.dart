import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/core/network/school_clients.dart';
import 'package:niu_mobile/features/moodle/course_detail_presentation.dart';
import 'package:niu_mobile/features/moodle/course_detail_widgets.dart';
import 'package:niu_mobile/features/moodle/course_presentation.dart';
import 'package:niu_mobile/features/moodle/course_widgets.dart';
import 'package:niu_mobile/features/moodle/moodle_repository.dart';
import 'package:niu_mobile/features/moodle/moodle_screen.dart';

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
  testWidgets('all six tabs including attendance load once until refresh', (
    tester,
  ) async {
    final loads = List.filled(6, 0);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CourseDetailTabs(
            builders: [
              for (var i = 0; i < 6; i++)
                (_) => CourseDetailList(
                  load: () async {
                    loads[i]++;
                    return [];
                  },
                  item: (_) => const SizedBox(),
                  emptyTitle: 'empty $i',
                  emptyMessage: 'message $i',
                ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(loads, [1, 0, 0, 0, 0, 0]);
    for (final label in ['出席', '教材', '出席', '成績', '出席', '公告']) {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }
    expect(loads, [1, 1, 0, 0, 1, 1]);
    await tester.drag(find.byType(ListView), const Offset(0, 350));
    await tester.pumpAndSettle();
    expect(loads, [2, 1, 0, 0, 1, 1]);
  });
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
    testWidgets('detail tabs accessible at 320px scale 2 in $brightness', (
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
      expect(repo.contentLoads, 0);
      expect(find.text('資料結構'), findsOneWidget);
      expect(find.text('資料結構 (1131_CS)'), findsNothing);
      expect(tester.takeException(), isNull);
      final list = find
          .descendant(
            of: find.byType(CourseDetailList),
            matching: find.byType(Scrollable),
          )
          .last;
      await tester.drag(list, const Offset(0, -500));
      await tester.pumpAndSettle();
      final position = tester.state<ScrollableState>(list).position.pixels;
      await tester.tap(find.text('教材'));
      await tester.pumpAndSettle();
      expect(find.text('9 月 6 日 – 9 月 12 日'), findsOneWidget);
      expect(find.byType(ExpansionTile), findsNothing);
      await tester.tap(find.text('第一週講義'));
      await tester.pumpAndSettle();
      expect(find.byType(MoodleModuleScreen), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('公告'));
      await tester.pumpAndSettle();
      expect(repo.announcementLoads, 1);
      expect(tester.state<ScrollableState>(list).position.pixels, position);
      await tester.tap(find.text('作業'));
      await tester.pumpAndSettle();
      expect(find.text('繳交狀態未提供'), findsOneWidget);
      await tester.tap(find.text('閱讀作業'));
      await tester.pumpAndSettle();
      expect(find.text('繳交狀態：繳交狀態未提供'), findsOneWidget);
      expect(find.text('評分：未提供'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pageBack();
      await tester.pumpAndSettle();
      final tabs = find
          .descendant(
            of: find.byType(CourseDetailTabs),
            matching: find.byType(SingleChildScrollView),
          )
          .first;
      await tester.drag(tabs, const Offset(-350, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('成績'));
      await tester.pumpAndSettle();
      expect(find.text('成績：尚未公布'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

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
