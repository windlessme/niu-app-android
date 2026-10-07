import 'custom_courses.dart';

class SchedulePeriod {
  const SchedulePeriod(
    this.label,
    this.time,
    this.courses, [
    this.custom = const {},
  ]);
  final String label;
  final String time;

  /// The school's cell text per day: teacher, course and room on lines.
  final Map<String, String> courses;

  /// Courses added on this device, per day, merged for display only.
  final Map<String, CustomCourse> custom;
}

class ClassSchedule {
  const ClassSchedule(this.days, this.periods);
  final List<String> days;
  final List<SchedulePeriod> periods;

  /// Supports both school table layouts: separate and combined period/time.
  factory ClassSchedule.fromRows(List<List<String>> rows) {
    if (rows.isEmpty) throw const FormatException('找不到課表');
    final start = rows.first.indexWhere((cell) => cell.contains('星期'));
    if (start < 1) throw const FormatException('課表欄位不符');
    final days = rows.first.skip(start).map((e) => e.trim()).toList();
    final periods = <SchedulePeriod>[];
    for (final row in rows.skip(1)) {
      if (row.length <= start) continue;
      final parts = row.first
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      if (parts.isEmpty) continue;
      final time = start >= 2 ? row[1].trim() : parts.skip(1).join('\n');
      periods.add(
        SchedulePeriod(parts.first, time, {
          for (var i = 0; i < days.length && i + start < row.length; i++)
            if (row[i + start].trim().isNotEmpty)
              days[i]: row[i + start].trim(),
        }),
      );
    }
    return ClassSchedule(days, periods);
  }
}
