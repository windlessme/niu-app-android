import '../../core/session/cached_schedule.dart';
import 'home_screen.dart';

/// Preserve the record type even when there is no cached timetable.
List<HomeCourse> todayCourses(
  CachedSchedule? schedule, {
  required DateTime now,
}) {
  if (schedule == null) return const [];
  final taipei = now.toUtc().add(const Duration(hours: 8));
  final minute = taipei.hour * 60 + taipei.minute;
  final result = <HomeCourse>[];
  for (final row in schedule.today(now: now)) {
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
