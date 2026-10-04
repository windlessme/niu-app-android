import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/features/moodle/course_presentation.dart';
import 'package:niu_mobile/features/moodle/course_widgets.dart';

void main() {
  final source = <String, dynamic>{
    'fullname': '資訊安全（進階）(1141_B4CS030018A)',
    'idnumber': '1141_B4CS030018A',
    'summary':
        '<p>開課教師：蘇維宗 助理教授 (suwt@niu.edu.tw); 學分數：3;</p><p>英文名稱：Information Security;</p><p>課程宗旨：完整宗旨與內容，不應出现在課程清單。</p><p>評分方式：期末專題 100%</p>',
  };
  test(
    'explicit source metadata preserves meaningful name and full syllabus',
    () {
      final course = CoursePresentation(source);
      expect(course.title, '資訊安全（進階）');
      expect(course.teacher, '蘇維宗 助理教授');
      expect(course.credits, '3 學分');
      expect(course.semester, '1141');
      expect(course.englishName, 'Information Security');
      expect(course.summary, contains('期末專題 100%'));
      expect(CoursePresentation({'summary': '教師可能給予三學分'}).teacher, '教師未提供');
      expect(CoursePresentation({}).credits, '學分未提供');
    },
  );
  for (final brightness in Brightness.values) {
    testWidgets('320px large text $brightness cards and full detail wrap', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Widget host(Widget child) => MaterialApp(
        theme: ThemeData(brightness: brightness),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 1000),
            textScaler: TextScaler.linear(2),
          ),
          child: Scaffold(body: SingleChildScrollView(child: child)),
        ),
      );
      final course = CoursePresentation(source);
      await tester.pumpWidget(
        host(MoodleCourseCard(course: course, onTap: () {})),
      );
      expect(find.textContaining('課程宗旨'), findsNothing);
      expect(find.text(course.title), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(host(MoodleCourseInformation(course: course)));
      expect(find.textContaining('完整宗旨與內容'), findsOneWidget);
      expect(find.textContaining('期末專題'), findsWidgets);
      expect(find.text('Information Security'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
