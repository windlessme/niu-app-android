import '../../core/session/cached_schedule.dart';
import '../schedule/custom_courses.dart';
import '../schedule/schedule_models.dart';
import '../schedule/schedule_presentation.dart';
import 'home_screen.dart';

/// Preserve the record type even when there is no cached timetable.
List<HomeCourse> todayCourses(
  CachedSchedule? schedule, {
  required DateTime now,
  List<CustomCourse> custom = const [],
}) {
  if (schedule == null) return const [];
  final taipei = now.toUtc().add(const Duration(hours: 8));
  final minute = taipei.hour * 60 + taipei.minute;
  final result = <HomeCourse>[];
  for (final row in _rows(schedule, taipei, custom, now)) {
    final times = RegExp(r'(\d{1,2}):(\d{2})').allMatches(row.time).toList();
    if (times.length < 2) continue;
    final start = int.parse(times[0][1]!) * 60 + int.parse(times[0][2]!);
    final end = int.parse(times[1][1]!) * 60 + int.parse(times[1][2]!);
    if (end <= minute) continue;
    final lines = row.course
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    result.add(
      HomeCourse(
        name: lines.length > 1 ? lines[1] : lines.firstOrNull ?? '',
        time: row.time,
        room: lines.length > 2 ? lines.skip(2).join(' ') : '',
        current: start <= minute,
      ),
    );
    if (result.length == 2) break;
  }
  return result;
}

/// Today's periods with a course, school cells as text and courses added on
/// this device written the same way (teacher line empty).
List<({String period, String time, String course})> _rows(
  CachedSchedule cached,
  DateTime taipei,
  List<CustomCourse> custom,
  DateTime now,
) {
  if (custom.isEmpty) return cached.today(now: now);
  try {
    final day = scheduleWeekdays[taipei.weekday - 1];
    final merged = ClassSchedule.fromRows(
      cached.rows,
    ).withCustomCourses(custom, taipei);
    return [
      for (final period in merged.periods)
        if (period.custom[day] case final course?)
          (
            period: period.label,
            time: period.time,
            course: '-\n${course.name}\n${course.classroom}',
          )
        else if ((period.courses[day] ?? '').trim().isNotEmpty)
          (
            period: period.label,
            time: period.time,
            course: period.courses[day]!,
          ),
    ];
  } on FormatException {
    return cached.today(now: now);
  }
}
