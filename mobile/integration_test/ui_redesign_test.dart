import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:niu_mobile/shared/shared.dart';
import 'package:niu_mobile/features/schedule/schedule_screen.dart';
import 'package:niu_mobile/features/graduation/graduation_screen.dart';
import 'package:niu_mobile/features/graduation/graduation_dashboard.dart';
import 'package:niu_mobile/features/moodle/course_presentation.dart';
import 'package:niu_mobile/features/moodle/course_widgets.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Android renders redesigned schedule, dashboard and course detail in both themes',
    (tester) async {
      final schedule = ClassSchedule.fromRows([
        ['節次', '時間', '星期二'],
        ['3', '10:10~11:00', '韓老師\n英文一\n綜202'],
        ['4', '11:10~12:00', '韓老師\n英文一\n綜202'],
      ]);
      final graduation = GraduationData.fromJson({
        'diverseHours': ['0', '20', '0', '20', '0', '20', '0', '40'],
        'creditRequired': ['128', '3'],
        'englishAbility': '尚未檢測',
        'physicalFitness': '已通過',
        'creditCourse': '',
      });
      for (final theme in [NiuTheme.dark, NiuTheme.light]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              appBar: const NiuAppBar(title: '我的課表'),
              body: ScheduleView(
                schedule: schedule,
                initialWeekday: 2,
                updatedAt: DateTime.now(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('英文一'), findsNWidgets(2));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              appBar: const NiuAppBar(title: '畢業門檻'),
              body: GraduationDashboard(data: graduation),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('graduation-overall')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              appBar: const NiuAppBar(title: 'M 園區'),
              body: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  MoodleCourseCard(
                    course: CoursePresentation({
                      'fullname': '計算機概論',
                      'shortname': '1151_B4CS000004A',
                      'teacher': '陳老師',
                      'credits': 3,
                      'summary': '授課目的完整說明',
                    }),
                    onTap: () {},
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('計算機概論'), findsOneWidget);
        expect(find.textContaining('授課目的'), findsNothing);
        expect(tester.takeException(), isNull);
      }
    },
  );
}
