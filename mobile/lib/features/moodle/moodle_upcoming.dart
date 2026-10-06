import 'moodle_repository.dart';

/// One assignment still to hand in, as listed under 即將截止.
class UpcomingAssignment {
  const UpcomingAssignment({
    required this.assignment,
    required this.courseName,
    required this.due,
  });

  /// The `mod_assign_get_assignments` entry; opens the assignment screen.
  final Json assignment;
  final String courseName;
  final DateTime due;
  int get id => number(assignment['id']);
  String get name => plain(assignment['name']);
}

enum UpcomingGroup {
  overdue('已逾期'),
  today('今天'),
  thisWeek('本週'),
  later('之後');

  const UpcomingGroup(this.label);
  final String label;
}

/// The same rules as the iOS app: assignments due from seven days ago to two
/// weeks ahead that are not submitted, grouped and labelled in Taipei time.
class UpcomingRules {
  const UpcomingRules._();

  static bool inWindow(DateTime due, DateTime now) =>
      !due.isBefore(now.subtract(const Duration(days: 7))) &&
      !due.isAfter(now.add(const Duration(days: 14)));

  static DateTime _taipei(DateTime instant) =>
      instant.toUtc().add(const Duration(hours: 8));

  /// Whole Taipei calendar days from [now]'s date to [due]'s date.
  static int _days(DateTime due, DateTime now) {
    final a = _taipei(now), b = _taipei(due);
    return DateTime.utc(
      b.year,
      b.month,
      b.day,
    ).difference(DateTime.utc(a.year, a.month, a.day)).inDays;
  }

  static UpcomingGroup group(DateTime due, DateTime now) {
    if (due.isBefore(now)) return UpcomingGroup.overdue;
    final days = _days(due, now);
    if (days == 0) return UpcomingGroup.today;
    // Weeks start on Monday.
    final untilSunday = DateTime.daysPerWeek - _taipei(now).weekday;
    return days <= untilSunday ? UpcomingGroup.thisWeek : UpcomingGroup.later;
  }

  static String deadline(DateTime due, DateTime now) {
    final local = _taipei(due);
    final time =
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
    final days = _days(due, now);
    if (due.isBefore(now)) {
      return days == 0 ? '已逾期・今天 $time' : '已逾期 ${-days} 天';
    }
    if (days == 0) return '今天 $time';
    if (days == 1) return '明天 $time';
    return '$days 天後';
  }

  /// Null when the status does not show this student's attempt (for
  /// example a teacher or a non-participant); the item is then left out.
  static bool? submitted(Json status) {
    final attempt = status['lastattempt'];
    if (attempt is! Map) return null;
    final states = [
      for (final key in ['submission', 'teamsubmission'])
        if (attempt[key] is Map && attempt[key]['status'] is String)
          attempt[key]['status'] as String,
    ];
    if (states.isEmpty ||
        !states.every(
          (s) => const {'new', 'draft', 'reopened', 'submitted'}.contains(s),
        )) {
      return null;
    }
    return states.contains('submitted');
  }
}

/// Loads the not-yet-submitted assignments of [courses] (id → name), soonest
/// first. Statuses are read four at a time.
Future<List<UpcomingAssignment>> loadUpcoming(
  MoodleRepository repository,
  Map<int, String> courses, {
  required DateTime now,
}) async {
  if (courses.isEmpty) return [];
  final candidates = <UpcomingAssignment>[];
  for (final assignment in await repository.assignmentsFor(
    courses.keys.toList(),
  )) {
    final course = int.tryParse('${assignment['course']}');
    final seconds = int.tryParse('${assignment['duedate']}') ?? 0;
    if (course == null || !courses.containsKey(course) || seconds <= 0) {
      continue;
    }
    final due = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
    if (!UpcomingRules.inWindow(due, now)) continue;
    candidates.add(
      UpcomingAssignment(
        assignment: assignment,
        courseName: courses[course]!,
        due: due,
      ),
    );
  }
  final pending = <UpcomingAssignment>[];
  for (var i = 0; i < candidates.length; i += 4) {
    final batch = candidates.skip(i).take(4);
    final states = await Future.wait(
      batch.map((item) async {
        return UpcomingRules.submitted(await repository.submission(item.id));
      }),
    );
    for (final (item, submitted) in [
      for (final (index, item) in batch.indexed) (item, states[index]),
    ]) {
      if (submitted == false) pending.add(item);
    }
  }
  pending.sort((a, b) {
    final order = a.due.compareTo(b.due);
    return order == 0 ? a.id.compareTo(b.id) : order;
  });
  return pending;
}
