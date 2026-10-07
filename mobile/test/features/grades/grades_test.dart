import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/core/session/campus_session.dart';
import 'package:niu_mobile/features/grades/grade_statistics.dart';
import 'package:niu_mobile/features/grades/grades_models.dart';
import 'package:niu_mobile/features/grades/grades_screen.dart';
import 'package:niu_mobile/features/grades/grades_widgets.dart';
import 'package:niu_mobile/shared/shared.dart';

import '../../support/fakes.dart';

void main() {
  test('ranks read as place/size whatever the page wraps them in', () {
    expect(formatRank('7/52'), '7/52');
    expect(formatRank(' 07 / 052 '), '7/52');
    expect(formatRank('第 7 名，共 52 人'), '7/52');
    expect(formatRank('7'), '7');
    expect(formatRank('第 名'), '');
    expect(formatRank(''), '');
  });

  test('history groups by term, newest first, with the summary attached', () {
    final courses = GradeCourse.parseHistoryRows([
      ['1141', '必修', '3', '微積分（一）', '76'],
      ['1142', '必修', '3', '離散數學', '82'],
      ['1133', '選修', '2', '暑期實習', '通過'],
      ['1142', '', '0', '體育－桌球', '88'],
    ]);
    final semesters = GradeSemester.group(courses, [
      {
        'sem': '1142',
        'classRank': '7/52',
        'departmentRank': '15 / 88',
        'average': '84.6',
      },
      {
        'sem': '1141',
        'classRank': '第 名',
        'departmentRank': '',
        'average': '尚未計算',
      },
    ]);
    expect([for (final s in semesters) s.shortLabel], ['114下', '114上', '113暑']);
    expect(semesters[0].rankLabel, '班排 7/52 · 系排 15/88');
    expect(semesters[0].average, 84.6);
    expect(semesters[0].courses.last.category, '體育');
    // No school rank or average yet: no rank, our own average.
    expect(semesters[1].rankLabel, '');
    expect(semesters[1].average, 76);
    expect(semesters[2].average, isNull);
  });

  test('歷年 ranks come from the summary table, not course rows', () {
    final dir = Directory.systemTemp.createTempSync('grade_history');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/scripts.json')
      ..writeAsStringSync(
        jsonEncode({'history': gradeExtractScript(GradeMode.history)}),
      );
    final result = Process.runSync('node', [
      'test/fixtures/grade_history_dom.cjs',
      file.path,
    ]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  });

  test('cached 歷年 snapshots from before ranks were mapped show no rank', () {
    final semesters = GradeSemester.group(
      GradeCourse.parseHistoryRows([
        ['1141', '必修', '3', '微積分（一）', '76'],
      ]),
      const [],
    );
    expect(semesters.single.rankLabel, '');
  });

  test('pass rate leaves textual grades out, like GPA', () {
    final stats = GradeStatistics([
      const GradeCourse(
        semester: '',
        name: 'A',
        type: '',
        score: '90',
        credits: 3,
      ),
      const GradeCourse(
        semester: '',
        name: 'B',
        type: '',
        score: '40',
        credits: 1,
      ),
      const GradeCourse(
        semester: '',
        name: 'C',
        type: '',
        score: '通過',
        credits: 2,
      ),
    ]);
    expect(stats.credits, 4);
    expect(stats.passRate, .75);
    expect(GradeStatistics(const []).passRate, isNull);
  });

  group('screen (demo data)', () {
    late CampusSession session;
    setUp(() async {
      session = CampusSession(vault: MemoryVault(), platformCleanup: []);
      await session.enterDemo();
    });
    tearDown(() => session.dispose());

    Future<void> open(WidgetTester tester, {bool dark = false}) async {
      tester.view.physicalSize = const Size(400, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: dark ? NiuTheme.dark : NiuTheme.light,
          home: GradesScreen(session: session),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('term grades show average, rank and course count', (
      tester,
    ) async {
      await open(tester);
      expect(find.text('學期平均'), findsOneWidget);
      expect(find.text('84.6'), findsOneWidget);
      expect(find.text('7/52'), findsOneWidget);
      expect(find.text('課程數'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      expect(find.widgetWithText(NiuBadge, '選修'), findsOneWidget);

      await tester.tap(find.text('期中'));
      await tester.pumpAndSettle();
      expect(find.text('期中平均'), findsOneWidget);
      // Neither is out yet.
      expect(find.text('—'), findsNWidgets(2));
    });

    for (final dark in [false, true]) {
      testWidgets('history: trend, filter and collapsed terms dark=$dark', (
        tester,
      ) async {
        await open(tester, dark: dark);
        await tester.tap(find.text('歷年'));
        await tester.pumpAndSettle();

        expect(find.text('累計 GPA（估算）'), findsOneWidget);
        expect(find.byType(GradeTrendChart), findsOneWidget);
        expect(find.text('班排 7/52 · 系排 15/88'), findsOneWidget);
        expect(find.text('班排 12/55 · 系排 21/85'), findsOneWidget);
        // The newest term is open; the older one shows its first course.
        expect(find.text('離散數學'), findsOneWidget);
        expect(find.text('程式設計（一）'), findsOneWidget);
        expect(find.text('微積分（一）'), findsNothing);
        await tester.tap(find.text('其餘 3 門課程'));
        await tester.pumpAndSettle();
        expect(find.text('微積分（一）'), findsOneWidget);

        await tester.tap(find.widgetWithText(NiuFilterChip, '114上'));
        await tester.pumpAndSettle();
        expect(find.text('學期 GPA（估算）'), findsOneWidget);
        expect(find.byType(GradeTrendChart), findsNothing);
        expect(find.text('離散數學'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
