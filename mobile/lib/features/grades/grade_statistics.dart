import 'grades_models.dart';

/// Local 4.3-scale estimate, matching the iOS numeric-score conversion.
/// Textual pass/exempt/withdrawn grades never enter the GPA denominator.
class GradeStatistics {
  GradeStatistics(Iterable<GradeCourse> courses) {
    for (final course in courses) {
      final score = double.tryParse(course.score);
      if (score == null ||
          !score.isFinite ||
          score < 0 ||
          score > 100 ||
          course.credits <= 0) {
        continue;
      }
      credits += course.credits;
      if (score >= 60) passedCredits += course.credits;
      _weighted += points(score) * course.credits;
      _score += score * course.credits;
    }
  }
  double credits = 0, passedCredits = 0, _weighted = 0, _score = 0;
  double? get gpa => credits == 0 ? null : _weighted / credits;
  double? get average => credits == 0 ? null : _score / credits;

  /// Share of graded credits passed; textual grades are left out as above.
  double? get passRate => credits == 0 ? null : passedCredits / credits;
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
