import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'schedule_models.dart';
import 'schedule_presentation.dart';

/// A course the student adds on this device, as on iOS. It is never sent to
/// the school or written into the school timetable cache; readers merge it
/// for display, widgets and reminders only.
class CustomCourse {
  const CustomCourse({
    required this.id,
    required this.name,
    this.classroom = '',
    this.note = '',
    required this.weekdays,
    required this.startPeriod,
    required this.endPeriod,
    required this.lastDay,
  });

  final String id, name, classroom, note;

  /// Monday-based: 0 = 星期一 … 6 = 星期日.
  final List<int> weekdays;

  /// The school's period labels, e.g. 「1」 or 「第 1 節」.
  final String startPeriod, endPeriod;

  /// Inclusive last day in Taipei, 「2027-01-31」.
  final String lastDay;

  static String newId() => List.generate(
    16,
    (_) => Random.secure().nextInt(16).toRadixString(16),
  ).join();

  factory CustomCourse.fromJson(Map json) => CustomCourse(
    id: '${json['id']}',
    name: '${json['name'] ?? ''}',
    classroom: '${json['classroom'] ?? ''}',
    note: '${json['note'] ?? ''}',
    weekdays: [
      for (final d in (json['weekdays'] as List? ?? []))
        if (d is int && d >= 0 && d < 7) d,
    ],
    startPeriod: '${json['startPeriod'] ?? ''}',
    endPeriod: '${json['endPeriod'] ?? ''}',
    lastDay: '${json['lastDay'] ?? ''}',
  );

  Map<String, Object> toJson() => {
    'id': id,
    'name': name,
    'classroom': classroom,
    'note': note,
    'weekdays': weekdays,
    'startPeriod': startPeriod,
    'endPeriod': endPeriod,
    'lastDay': lastDay,
  };

  static String day(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  static DateTime? date(String value) {
    final parts = value.split('-').map(int.tryParse).toList();
    if (parts.length != 3 || parts.any((p) => p == null)) return null;
    return DateTime(parts[0]!, parts[1]!, parts[2]!);
  }

  /// Shown through its last day, gone the day after.
  bool activeOn(DateTime date) => day(date).compareTo(lastDay) <= 0;

  /// Row indices in [periods]; null when either period no longer exists.
  (int, int)? rows(List<SchedulePeriod> periods) {
    final start = periods.indexWhere((p) => p.label == startPeriod);
    final end = periods.indexWhere((p) => p.label == endPeriod);
    return start < 0 || end < start ? null : (start, end);
  }

  static const shortWeekdays = ['一', '二', '三', '四', '五', '六', '日'];

  /// 「每週一、三」
  static String weekdaySummary(Iterable<int> weekdays) =>
      '每週${(weekdays.toSet().toList()..sort()).where((d) => d >= 0 && d < 7).map((d) => shortWeekdays[d]).join('、')}';

  /// 「第 7–8 節 15:10–16:55」
  static String periodSummary(List<SchedulePeriod> periods) {
    if (periods.isEmpty) return '';
    final first = schedulePeriodNumber(periods.first.label);
    final last = schedulePeriodNumber(periods.last.label);
    final label = periods.length == 1 ? '第 $first 節' : '第 $first–$last 節';
    final start = _clocks(periods.first.time).firstOrNull;
    final end = _clocks(periods.last.time).lastOrNull;
    return start == null || end == null ? label : '$label $start–$end';
  }

  static List<String> _clocks(String text) => [
    for (final m in RegExp(r'\d{1,2}:\d{2}').allMatches(text)) m[0]!,
  ];

  /// 「每週一、三・第 7–8 節 15:10–16:55」
  String summary(List<SchedulePeriod> periods) {
    final days = weekdaySummary(weekdays);
    final range = rows(periods);
    if (range == null) return days;
    return '$days・${periodSummary(periods.sublist(range.$1, range.$2 + 1))}';
  }

  String get lastDayLabel => lastDay.replaceAll('-', '/');
}

extension CustomCourseMerge on ClassSchedule {
  /// Places the courses active in the Monday-based week containing [date]
  /// into empty slots. School courses keep their slot; a custom course whose
  /// slot is taken is skipped for that day rather than shown in part.
  ClassSchedule withCustomCourses(List<CustomCourse> courses, DateTime date) {
    if (courses.isEmpty) return this;
    final monday = DateTime(date.year, date.month, date.day - date.weekday + 1);
    final custom = [for (final _ in periods) <String, CustomCourse>{}];
    final daysUsed = <String>{};
    for (final course in courses) {
      final range = course.rows(periods);
      if (range == null) continue;
      for (final weekday in course.weekdays.toSet()) {
        if (weekday < 0 || weekday > 6) continue;
        if (!course.activeOn(monday.add(Duration(days: weekday)))) continue;
        final day = scheduleWeekdays[weekday];
        final free = [
          for (var row = range.$1; row <= range.$2; row++)
            (periods[row].courses[day] ?? '').trim().isEmpty &&
                custom[row][day] == null,
        ].every((f) => f);
        if (!free) continue;
        for (var row = range.$1; row <= range.$2; row++) {
          custom[row][day] = course;
        }
        daysUsed.add(day);
      }
    }
    if (daysUsed.isEmpty) return this;
    return ClassSchedule(
      [
        ...days,
        for (final day in scheduleWeekdays)
          if (daysUsed.contains(day) && !days.contains(day)) day,
      ],
      [
        for (final (i, period) in periods.indexed)
          SchedulePeriod(period.label, period.time, period.courses, {
            ...period.custom,
            ...custom[i],
          }),
      ],
    );
  }

  /// The first slot already used by a school course or by another custom
  /// course still shown, as text for the student; null when all are free.
  String? conflict(
    CustomCourse course,
    List<CustomCourse> others,
    DateTime today,
  ) {
    final range = course.rows(periods);
    if (range == null) return '找不到所選節次';
    final todayKey = CustomCourse.day(today);
    for (final weekday in course.weekdays.toSet().toList()..sort()) {
      final day = scheduleWeekdays[weekday];
      for (var row = range.$1; row <= range.$2; row++) {
        final school = schedulePeriodLessonName(periods[row].courses[day]);
        if (school != null) {
          return '$day第 ${schedulePeriodNumber(periods[row].label)} 節已有「$school」';
        }
      }
      for (final other in others) {
        if (other.id == course.id ||
            other.lastDay.compareTo(todayKey) < 0 ||
            !other.weekdays.contains(weekday)) {
          continue;
        }
        final theirs = other.rows(periods);
        if (theirs == null || theirs.$2 < range.$1 || range.$2 < theirs.$1) {
          continue;
        }
        final row = max(range.$1, theirs.$1);
        return '$day第 ${schedulePeriodNumber(periods[row].label)} 節已有自訂課程「${other.name}」';
      }
    }
    return null;
  }
}

/// The course name in a school cell (teacher, name, room on separate lines).
String? schedulePeriodLessonName(String? cell) {
  final lines = (cell ?? '')
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();
  if (lines.isEmpty) return null;
  return lines.length > 1 ? lines[1] : lines.first;
}

/// Device-local custom courses, kept per account like iOS: logging out
/// keeps each account's own courses for when it signs in again.
class CustomCourseStore extends ChangeNotifier {
  CustomCourseStore._();
  static final instance = CustomCourseStore._();
  static const key = 'customCourses.byAccount.v1';

  String? _account;
  List<CustomCourse> _courses = const [];
  bool _loaded = false;

  /// The signed-in account's courses; empty until [load] has run.
  List<CustomCourse> coursesFor(String? account) =>
      account != null && account == _account ? _courses : const [];

  Future<Map<String, List<CustomCourse>>> _all() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(key);
      final data = raw == null ? null : jsonDecode(raw);
      if (data is! Map) return {};
      return {
        for (final entry in data.entries)
          if (entry.value is List)
            '${entry.key}': [
              for (final c in (entry.value as List).whereType<Map>())
                CustomCourse.fromJson(c),
            ],
      };
    } catch (_) {
      return {};
    }
  }

  Future<void> load(String? account) async {
    if (account == null) {
      if (_account != null || _courses.isNotEmpty) {
        _account = null;
        _courses = const [];
        notifyListeners();
      }
      return;
    }
    if (_loaded && account == _account) return;
    final all = await _all();
    _account = account;
    _courses = List.unmodifiable(all[account] ?? const []);
    _loaded = true;
    notifyListeners();
  }

  Future<void> _persist(String account, List<CustomCourse> list) async {
    final all = await _all();
    if (list.isEmpty) {
      all.remove(account);
    } else {
      all[account] = list;
    }
    await (await SharedPreferences.getInstance()).setString(
      key,
      jsonEncode({
        for (final e in all.entries)
          e.key: [for (final c in e.value) c.toJson()],
      }),
    );
    _account = account;
    _courses = List.unmodifiable(list);
    _loaded = true;
    notifyListeners();
  }

  Future<void> save(String account, CustomCourse course) async {
    await load(account);
    final list = [..._courses];
    final i = list.indexWhere((c) => c.id == course.id);
    i < 0 ? list.add(course) : list[i] = course;
    await _persist(account, list);
  }

  Future<void> delete(String account, String id) async {
    await load(account);
    await _persist(account, [..._courses.where((c) => c.id != id)]);
  }

  @visibleForTesting
  void reset() {
    _account = null;
    _courses = const [];
    _loaded = false;
  }
}
