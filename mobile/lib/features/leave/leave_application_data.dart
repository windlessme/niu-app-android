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
    this.selected = false,
  });
  final String value, date, period, course;
  final bool selected;
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
