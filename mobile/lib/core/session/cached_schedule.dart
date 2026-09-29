/// Account-scoped timetable. Dates and today's courses use Taipei civil time.
class CachedSchedule {
  CachedSchedule({
    required this.account,
    required this.fetchedAt,
    required this.rows,
  });
  final String account;
  final DateTime fetchedAt;
  final List<List<String>> rows;
  Map<String, dynamic> toJson() => {
    'account': account,
    'fetchedAt': fetchedAt.toIso8601String(),
    'rows': rows,
  };
  factory CachedSchedule.fromJson(Map<String, dynamic> value) => CachedSchedule(
    account: value['account'] as String,
    fetchedAt: DateTime.parse(value['fetchedAt'] as String),
    rows: (value['rows'] as List)
        .map((r) => (r as List).cast<String>())
        .toList(),
  );

  /// ISO weekday (Monday=1). Each entry preserves school period, time and text.
  List<({String period, String time, String course})> coursesForWeekday(
    int weekday,
  ) {
    const names = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
    if (rows.isEmpty || weekday < 1 || weekday > 7) return [];
    final column = rows.first.indexWhere((v) => v.trim() == names[weekday - 1]);
    final firstDay = rows.first.indexWhere((v) => v.contains('星期'));
    if (column < 0) return [];
    return [
      for (final row in rows.skip(1))
        if (row.length > column && row[column].trim().isNotEmpty)
          (
            period: row.first.split('\n').first.trim(),
            time: firstDay >= 2
                ? row[1]
                : row.first.split('\n').skip(1).join('\n'),
            course: row[column].trim(),
          ),
    ];
  }

  List<({String period, String time, String course})> today({DateTime? now}) =>
      coursesForWeekday(
        (now ?? DateTime.now()).toUtc().add(const Duration(hours: 8)).weekday,
      );
}
