import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/core/session/cached_schedule.dart';
import 'package:niu_mobile/features/home/today_courses.dart';

void main() {
  test(
    'home converts restored JSON timetable without dynamic predicate errors',
    () {
      final cache = CachedSchedule.fromJson(
        jsonDecode('''{
      "account":"fixture", "fetchedAt":"2026-09-28T00:00:00Z",
      "rows":[["節次","時間","星期二"],
        ["1","08:10~09:00","教師甲\\n 資料結構 \\n\\n A101 "],
        ["2","09:10~10:00","教師乙\\n微積分\\nB202"],
        ["3","10:10~11:00","教師丙\\n英文\\nC303"]]
    }''')
            as Map<String, dynamic>,
      );
      final courses = todayCourses(
        cache,
        now: DateTime.utc(2026, 9, 29, 0, 30),
      );
      expect(courses.map((c) => c.name), ['資料結構', '微積分']);
      expect(courses.first.room, 'A101');
      expect(courses.first.current, isTrue);
      expect(courses.last.current, isFalse);
      expect(todayCourses(cache, now: DateTime.utc(2026, 9, 29, 4)), isEmpty);
      expect(todayCourses(null, now: DateTime.utc(2026, 9, 29)), isEmpty);
    },
  );
}
