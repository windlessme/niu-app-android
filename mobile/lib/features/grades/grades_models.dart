import 'grade_statistics.dart';

enum GradeMode { midterm, finalTerm, history }

class GradeCourse {
  const GradeCourse({
    required this.semester,
    required this.name,
    required this.type,
    required this.score,
    this.credits = 0,
    this.semesterKey = '',
  });
  final String semester, name, type, score;
  final double credits;

  /// The school's compact term code, e.g. `1142`; empty outside 歷年.
  final String semesterKey;
  bool get failed => double.tryParse(score) != null && double.parse(score) < 60;

  /// The school's course type, or a guess from the name when it has none.
  String get category => type.isNotEmpty
      ? type
      : name.contains('體育')
      ? '體育'
      : '其他';

  /// `115`, `1` → `115 學年度 上學期`; empty when the parts aren't a term.
  static String semesterLabel(String year, String term) {
    final name = {'1': '上', '2': '下', '3': '暑'}[term.trim()];
    return RegExp(r'^\d{2,3}$').hasMatch(year.trim()) && name != null
        ? '${year.trim()} 學年度 $name學期'
        : '';
  }

  static List<GradeCourse> parseHistoryRows(List<List<String>> rows) {
    final result = <GradeCourse>[];
    for (final row in rows) {
      if (row.length < 5) continue;
      final sem = RegExp(r'^(\d{2,3})([123])$').firstMatch(row[0].trim());
      if (sem == null || row[3].trim().isEmpty || row[4].trim().isEmpty) {
        continue;
      }
      final term = {'1': '上', '2': '下', '3': '暑'}[sem[2]]!;
      result.add(
        GradeCourse(
          semester: '${sem[1]} 學年度 $term學期',
          semesterKey: sem[0]!,
          type: row[1].trim(),
          credits: double.tryParse(row[2]) ?? 0,
          name: row[3].trim(),
          score: row[4].trim(),
        ),
      );
    }
    return result;
  }
}

/// One term of 歷年 grades, with the school's rank and average when listed.
class GradeSemester {
  GradeSemester({
    required this.key,
    required this.courses,
    this.rank = '',
    this.schoolAverage,
  });

  /// `1142` → 114 學年度下學期.
  final String key;
  final List<GradeCourse> courses;
  final String rank;
  final double? schoolAverage;
  late final stats = GradeStatistics(courses);

  int get year => int.parse(key.substring(0, key.length - 1));
  String get term => {'1': '上', '2': '下', '3': '暑'}[key[key.length - 1]]!;

  /// `114下`, for filter chips and the trend axis.
  String get shortLabel => '$year$term';
  String get termTitle => '$term學期';

  /// The school's term average, or ours from numeric grades.
  double? get average => schoolAverage ?? stats.average;

  /// Groups 歷年 courses by term, newest first, and attaches the summary
  /// table's rank (column 3) and average (column 4) to each term.
  static List<GradeSemester> group(
    Iterable<GradeCourse> courses,
    Iterable<List> summary,
  ) {
    final byKey = <String, List<GradeCourse>>{};
    for (final c in courses) {
      if (c.semesterKey.isEmpty) continue;
      byKey.putIfAbsent(c.semesterKey, () => []).add(c);
    }
    final ranks = {
      for (final s in summary)
        if (s.length >= 4) '${s[0]}'.trim(): s,
    };
    final keys = byKey.keys.toList()
      ..sort((a, b) => int.parse(b).compareTo(int.parse(a)));
    return [
      for (final key in keys)
        GradeSemester(
          key: key,
          courses: byKey[key]!,
          rank: formatRank('${ranks[key]?[2] ?? ''}'),
          schoolAverage: double.tryParse(
            '${ranks[key]?[3] ?? ''}'.replaceAll(',', '').trim(),
          ),
        ),
    ];
  }
}

/// `7 / 52`, `第 7 名，共 52 人` → `7/52`; a lone number stays as is. Empty
/// when there is no number, as on the page before ranks are out (「第 名」).
String formatRank(String raw) {
  final numbers = [
    for (final m in RegExp(r'\d+').allMatches(raw)) int.parse(m[0]!),
  ];
  final slash = RegExp(r'(\d+)\s*/\s*(\d+)').firstMatch(raw);
  if (slash != null) return '${int.parse(slash[1]!)}/${int.parse(slash[2]!)}';
  if (numbers.length >= 2) return '${numbers.first}/${numbers.last}';
  return numbers.isEmpty ? '' : '${numbers.single}';
}
