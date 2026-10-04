/// Values are read from the currently authenticated school form, not inferred
/// from the cached timetable or a local copy of the school's leave rules.
class LeaveChoice {
  const LeaveChoice(this.value, this.label);
  final String value, label;
  bool get personal =>
      value.isNotEmpty && value != '003' && !label.contains('公假');
}

class LeavePeriodChoice {
  const LeavePeriodChoice({
    required this.value,
    required this.date,
    required this.period,
    required this.course,
    this.teacher = '',
    this.room = '',
    this.selected = false,
  });
  final String value, date, period, course, teacher, room;
  final bool selected;
}

/// One period of a leave, as the school lists it on the form, in the
/// detail page or in the picker.
class LeavePeriodEntry {
  const LeavePeriodEntry({
    required this.date,
    required this.period,
    this.course = '',
    this.teacher = '',
    this.room = '',
  });
  final String date, period, course, teacher, room;

  /// 「第 3 節」 → 3; the school writes the period as 3, 第3節 or 3 08:10~09:00.
  int? get number => leavePeriodNumber(period);

  /// Start–end clock when the school's period label carries it.
  String get time => leavePeriodTime(period);
}

int? leavePeriodNumber(String period) {
  final m = RegExp(r'^\D{0,2}?(\d{1,2})(?!\d|:)').firstMatch(period.trim());
  return m == null ? null : int.tryParse(m[1]!);
}

String leavePeriodTime(String period) {
  final m = RegExp(
    r'(\d{1,2}:\d{2})\s*[~～\-–－]\s*(\d{1,2}:\d{2})',
  ).firstMatch(period);
  return m == null ? '' : '${m[1]}–${m[2]}';
}

/// 「第 3 節」, 「第 3–4 節」 or the school's own text when it is not a number.
String leavePeriodLabel(Iterable<String> periods) {
  final list = periods.toList();
  final numbers = list.map(leavePeriodNumber).toList();
  if (list.isEmpty) return '';
  if (numbers.any((n) => n == null)) return list.join('、');
  return numbers.first == numbers.last
      ? '第 ${numbers.first} 節'
      : '第 ${numbers.first}–${numbers.last} 節';
}

/// Reads a school period table. Columns are found by their header (the
/// first row, or [headers]); without one, by what each cell looks like.
List<LeavePeriodEntry> leavePeriodEntries(
  List<List<String>> rows, {
  List<String> headers = const [],
}) {
  var body = rows;
  var head = headers;
  if (head.isEmpty &&
      rows.isNotEmpty &&
      rows.first.any((c) => c.contains('節次') || c.contains('請假日期'))) {
    head = rows.first;
    body = rows.skip(1).toList();
  }
  int column(bool Function(String h) test) => head.indexWhere(test);
  final at = (
    date: column((h) => h.contains('日期')),
    period: column((h) => h.contains('節次')),
    course: column((h) => h.contains('課程名稱') || h.contains('科目') || h == '課程'),
    teacher: column((h) => h.contains('教師') || h.contains('老師')),
    room: column((h) => h.contains('教室')),
  );
  String cell(List<String> row, int i) =>
      i >= 0 && i < row.length ? row[i].trim() : '';
  bool isDate(String c) =>
      parseSchoolLeaveDate(c) != null ||
      RegExp(r'^\d{7}$').hasMatch(c) ||
      RegExp(r'^\d{1,2}/\d{1,2}').hasMatch(c);
  bool isPeriod(String c) => RegExp(r'^第?\s*\d{1,2}\s*節?$').hasMatch(c);
  final result = <LeavePeriodEntry>[];
  for (final row in body) {
    if (row.every((c) => c.trim().isEmpty)) continue;
    if (head.isNotEmpty && at.date >= 0 && at.period >= 0) {
      result.add(
        LeavePeriodEntry(
          date: _rocDate(cell(row, at.date)),
          period: cell(row, at.period),
          course: cell(row, at.course),
          teacher: cell(row, at.teacher),
          room: cell(row, at.room),
        ),
      );
      continue;
    }
    final cells = [for (final c in row) c.trim()];
    final date = cells.firstWhere(isDate, orElse: () => '');
    final period = cells.firstWhere(isPeriod, orElse: () => '');
    final words = [
      for (final c in cells)
        if (c.isNotEmpty &&
            c != date &&
            c != period &&
            RegExp(r'[^\d\s/:~\-]').hasMatch(c))
          c,
    ];
    if (date.isEmpty && period.isEmpty) continue;
    result.add(
      LeavePeriodEntry(
        date: _rocDate(date),
        period: period,
        course: words.firstOrNull ?? '',
        teacher: words.length > 1 ? words[1] : '',
      ),
    );
  }
  return result;
}

/// The school writes the same date as 115/10/08 or 1151008.
String _rocDate(String value) {
  final m = RegExp(r'^(\d{3})(\d{2})(\d{2})$').firstMatch(value.trim());
  return m == null ? value.trim() : '${m[1]}/${m[2]}/${m[3]}';
}

/// 「10/8（三）」 for a school date, or the text as given.
String leaveDayLabel(String value) {
  final date = parseSchoolLeaveDate(value);
  if (date == null) return value;
  return '${date.month}/${date.day}（${'一二三四五六日'[date.weekday - 1]}）';
}

class LeaveApplicationData {
  const LeaveApplicationData({
    required this.revision,
    this.notice,
    this.choices = const [],
    this.type = '',
    this.start = '',
    this.end = '',
    this.reason = '',
    this.reasonLimit = 1000,
    this.later = false,
    this.canDeferAttachment = false,
    this.periods = const [],
    this.periodHeaders = const [],
    this.total,
    this.attachments = const [],
    this.extensions = const [],
  });
  final String revision;
  final String? notice;
  final List<LeaveChoice> choices;
  final String type, start, end, reason;
  final int reasonLimit;
  final bool later, canDeferAttachment;

  /// School-rendered rows after the period picker has returned its values.
  final List<List<String>> periods;

  /// Header cells of the school's period table, naming each column.
  final List<String> periodHeaders;
  List<LeavePeriodEntry> get periodEntries =>
      leavePeriodEntries(periods, headers: periodHeaders);
  final String? total;
  final List<String> attachments, extensions;
  bool get hasPeriods => periods.isNotEmpty;
  String get typeLabel =>
      choices.where((c) => c.value == type).firstOrNull?.label ?? '-';

  factory LeaveApplicationData.fromJson(Map<String, dynamic> data) {
    final revision = data['revision'];
    if (revision is! String || revision.isEmpty) {
      throw const FormatException('Missing school form revision');
    }
    if (data['notice'] case final String notice) {
      return LeaveApplicationData(revision: revision, notice: notice);
    }
    final choices = <LeaveChoice>[
      for (final c in (data['choices'] as List).cast<Map>())
        LeaveChoice(c['value'] as String, c['label'] as String),
    ].where((c) => c.personal).toList();
    final max = data['reasonLimit'];
    if (max is! int || max <= 0 || max > 10000) {
      throw const FormatException('Unknown reason limit');
    }
    return LeaveApplicationData(
      revision: revision,
      choices: List.unmodifiable(choices),
      type: data['type'] as String,
      start: data['start'] as String,
      end: data['end'] as String,
      reason: data['reason'] as String,
      reasonLimit: max,
      later: data['later'] == true,
      canDeferAttachment: data['canDeferAttachment'] == true,
      periods: [
        for (final row in data['periods'] as List)
          List<String>.unmodifiable((row as List).cast<String>()),
      ],
      periodHeaders: List<String>.unmodifiable(
        ((data['periodHeaders'] as List?) ?? const []).cast<String>(),
      ),
      total: data['total'] as String?,
      attachments: List<String>.unmodifiable(
        (data['attachments'] as List).cast<String>(),
      ),
      extensions: List<String>.unmodifiable(
        (data['extensions'] as List).cast<String>(),
      ),
    );
  }

  String? validate(String text) {
    if (!choices.any((c) => c.value == type)) return '請選擇假別';
    final from = parseSchoolLeaveDate(start), to = parseSchoolLeaveDate(end);
    if (from == null || to == null || to.isBefore(from)) return '請確認請假日期';
    if (!hasPeriods) return '請選擇請假節次';
    if (text.trim().isEmpty) return '請填寫請假事由';
    if (text.length > reasonLimit) return '請假事由超過校方字數限制';
    return null;
  }
}

DateTime? parseSchoolLeaveDate(String text) {
  final m = RegExp(r'^(\d{3,4})/(\d{1,2})/(\d{1,2})$').firstMatch(text.trim());
  if (m == null) return null;
  var year = int.parse(m[1]!);
  if (m[1]!.length == 3) year += 1911;
  final month = int.parse(m[2]!), day = int.parse(m[3]!);
  final date = DateTime(year, month, day);
  return date.year == year && date.month == month && date.day == day
      ? date
      : null;
}

String schoolLeaveDate(DateTime date) =>
    '${date.year - 1911}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';

String displayLeaveDate(String value) {
  final date = parseSchoolLeaveDate(value);
  return date == null
      ? (value.isEmpty ? '選擇日期' : value)
      : '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
}

class LeaveSubmitResult {
  const LeaveSubmitResult({this.applicationId, required this.message});
  final String? applicationId;
  final String message;
  bool get confirmed => applicationId != null;
}

class LeaveApplicationException implements Exception {
  const LeaveApplicationException(this.message);
  final String message;
  @override
  String toString() => message;
}
