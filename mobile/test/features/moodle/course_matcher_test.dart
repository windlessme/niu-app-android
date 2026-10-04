import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/features/moodle/course_matcher.dart';
import 'package:niu_mobile/features/moodle/course_presentation.dart';

CoursePresentation course(String name, String code) =>
    CoursePresentation({'fullname': name, 'shortname': code});

void main() {
  final courses = [
    course('微積分（一）', '1141_B1MA0001'),
    course('微積分(二)', '1142_B1MA0002'),
    course('資料結構', '1141_B4CS0001'),
    course('資料結構', '1151_B4CS0001'),
    course('英文一 (1151_B0EN0001)', '1151_B0EN0001'),
    course('計算機網路實驗', '1151_B4CS0009'),
  ];

  test('exact names match, keeping 一 and 二 apart', () {
    expect(matchMoodleCourse(courses, '微積分(一)')!.code, '1141_B1MA0001');
    expect(matchMoodleCourse(courses, '微積分（二）')!.code, '1142_B1MA0002');
  });

  test('the most recent semester wins between same-named courses', () {
    expect(matchMoodleCourse(courses, '資料結構')!.code, '1151_B4CS0001');
  });

  test('course codes in titles and partial names still match', () {
    expect(matchMoodleCourse(courses, '英文一')!.code, '1151_B0EN0001');
    expect(matchMoodleCourse(courses, '計算機網路')!.code, '1151_B4CS0009');
  });

  test('unknown or empty names do not match anything', () {
    expect(matchMoodleCourse(courses, '體育'), isNull);
    expect(matchMoodleCourse(courses, '  '), isNull);
  });
}
