import 'schedule_models.dart';

const scheduleWeekdays = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];

/// A display-only block. The school API has no course ID or occurrence date:
/// identity therefore falls back to (name, teacher, room), within one day key.
/// Never infer identity from the title alone or merge across day/date keys.
class ScheduleLesson {
  const ScheduleLesson({
    required this.day,
    required this.name,
    required this.teacher,
    required this.room,
    required this.periods,
    required this.start,
    required this.end,
    this.customId,
    this.colorId,
  });

  /// Set for a course added on this device rather than by the school.
  final String? customId;

  /// A custom course's chosen colour (see `customCourseTint`).
  final String? colorId;
  final String day;
  final String name;
  final String teacher;
  final String room;
  final List<String> periods;
  final String start;
  final String end;

  String get periodLabel {
    if (periods.isEmpty) return '節次未提供';
    final first = _periodText(periods.first);
    if (periods.length == 1) return '第 $first 節';
    return '第 $first–${_periodText(periods.last)} 節';
  }
}

/// 「第 3 節」 or 「3」 → 「3」, for compact period labels.
String schedulePeriodNumber(String label) => _periodText(label);

String _periodText(String label) => label
    .trim()
    .replaceFirst(RegExp(r'^第\s*'), '')
    .replaceFirst(RegExp(r'\s*節$'), '')
    .trim();

int? _number(String label) {
  final text = _periodText(label);
  final arabic = int.tryParse(text);
  if (arabic != null) return arabic;
  const digits = {
    '一': 1,
    '二': 2,
    '三': 3,
    '四': 4,
    '五': 5,
    '六': 6,
    '七': 7,
    '八': 8,
    '九': 9,
  };
  if (digits.containsKey(text)) return digits[text];
  if (text == '十') return 10;
  final parts = text.split('十');
  if (parts.length != 2) return null;
  final tens = parts.first.isEmpty ? 1 : digits[parts.first];
  final units = parts.last.isEmpty ? 0 : digits[parts.last];
  return tens == null || units == null ? null : tens * 10 + units;
}

List<ScheduleLesson> scheduleLessons(
  ClassSchedule schedule,
  String day, {
  bool mergeConsecutive = false,
}) {
  final result = <ScheduleLesson>[];
  ScheduleLesson? pending;
  void flush() {
    if (pending != null) result.add(pending!);
    pending = null;
  }

  for (final period in schedule.periods) {
    final custom = period.custom[day];
    final lines = (period.courses[day] ?? '')
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (lines.isEmpty && custom == null) {
      flush();
      continue;
    }
    // A device-added course carries its own fields; school cells are text.
    final teacher = custom != null
        ? custom.note
        : lines.length > 1
        ? lines.first
        : '';
    final name = custom?.name ?? (lines.length > 1 ? lines[1] : lines.first);
    final room = custom?.classroom ?? lines.skip(2).join(' ');
    final times = RegExp(
      r'\d{1,2}:\d{2}',
    ).allMatches(period.time).map((match) => match.group(0)!).toList();
    final start = times.isEmpty ? '—' : times.first;
    final end = times.length < 2 ? '—' : times.last;
    final previous = pending;
    final number = _number(period.label);
    final previousNumber = previous == null
        ? null
        : _number(previous.periods.last);
    if (mergeConsecutive &&
        previous != null &&
        number != null &&
        previousNumber != null &&
        number == previousNumber + 1 &&
        previous.day == day &&
        previous.name == name &&
        previous.teacher == teacher &&
        previous.room == room &&
        previous.customId == custom?.id) {
      pending = ScheduleLesson(
        day: day,
        name: name,
        teacher: teacher,
        room: room,
        periods: [...previous.periods, period.label],
        start: previous.start,
        end: end,
        customId: previous.customId,
        colorId: previous.colorId,
      );
    } else {
      flush();
      pending = ScheduleLesson(
        day: day,
        name: name,
        teacher: teacher,
        room: room,
        periods: [period.label],
        start: start,
        end: end,
        customId: custom?.id,
        colorId: custom?.colorId,
      );
    }
  }
  flush();
  return result;
}
