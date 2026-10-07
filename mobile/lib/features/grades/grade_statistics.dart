import 'grades_models.dart';

/// Local 4.3-scale estimate, matching the iOS numeric-score conversion.
/// Textual pass/exempt/withdrawn grades never enter the GPA denominator,
/// but 通過 and 抵免 still count as earned credits.
class GradeStatistics {
  GradeStatistics(Iterable<GradeCourse> courses) {
    for (final course in courses) {
      if (course.credits <= 0) continue;
      final score = double.tryParse(course.score);
      if (score == null) {
        final passed = textPassed(course.score);
        if (passed == null) continue;
        attemptedCredits += course.credits;
        if (passed) earnedCredits += course.credits;
        continue;
      }
      if (!score.isFinite || score < 0 || score > 100) continue;
      credits += course.credits;
      attemptedCredits += course.credits;
      if (score >= 60) earnedCredits += course.credits;
      _weighted += points(score) * course.credits;
      _score += score * course.credits;
    }
  }

  /// Credits with a numeric grade: the GPA and average denominator.
  double credits = 0, _weighted = 0, _score = 0;

  /// Credits with a final result, numeric or 通過/抵免/不通過, and those passed.
  double attemptedCredits = 0, earnedCredits = 0;
  double? get gpa => credits == 0 ? null : _weighted / credits;
  double? get average => credits == 0 ? null : _score / credits;

  /// Share of decided credits earned.
  double? get passRate =>
      attemptedCredits == 0 ? null : earnedCredits / attemptedCredits;

  /// Whether a textual grade passed; null when it isn't a result at all
  /// (停修, 尚未公布, blank).
  static bool? textPassed(String text) {
    if (text.contains('不通過') || text.contains('不及格')) return false;
    if (['通過', '及格', '抵免', '免修'].any(text.contains)) return true;
    return null;
  }

  /// The 4.3 scale shown in the GPA explanation, highest first.
  static const bands = [
    ('90–100', 'A+', 4.3),
    ('85–89', 'A', 4.0),
    ('80–84', 'A-', 3.7),
    ('77–79', 'B+', 3.3),
    ('73–76', 'B', 3.0),
    ('70–72', 'B-', 2.7),
    ('67–69', 'C+', 2.3),
    ('63–66', 'C', 2.0),
    ('60–62', 'C-', 1.7),
    ('0–59', 'F', 0.0),
  ];

  static double points(double score) {
    if (score > 100 || score < 60) return 0;
    for (final boundary in [
      (90, 4.3),
      (85, 4.0),
      (80, 3.7),
      (77, 3.3),
      (73, 3.0),
      (70, 2.7),
      (67, 2.3),
      (63, 2.0),
      (60, 1.7),
    ]) {
      if (score >= boundary.$1) return boundary.$2;
    }
    return 0;
  }
}
