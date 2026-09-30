import 'course_presentation.dart';

/// Normalizes width, brackets and spacing, but keeps bracket contents so
/// 微積分（一） and 微積分（二） stay different courses.
String normalizeCourseName(String value) {
  final buffer = StringBuffer();
  for (final rune in value.runes) {
    // Full-width ASCII variants (e.g. （ ） Ａ １) to half width.
    final r = rune >= 0xff01 && rune <= 0xff5e ? rune - 0xfee0 : rune;
    buffer.writeCharCode(r);
  }
  return buffer
      .toString()
      .replaceAll(RegExp(r'[\s　]+'), '')
      .replaceAll(RegExp(r'[【\[]'), '(')
      .replaceAll(RegExp(r'[】\]]'), ')')
      .toLowerCase();
}

/// Finds the M 園區 course for a timetable entry. Exact names win, then
/// one name containing the other; ties go to the most recent semester.
CoursePresentation? matchMoodleCourse(
  Iterable<CoursePresentation> courses,
  String scheduleName,
) {
  final wanted = normalizeCourseName(scheduleName);
  if (wanted.isEmpty) return null;
  CoursePresentation? best;
  var bestScore = 0;
  for (final course in courses) {
    final names = {
      normalizeCourseName(course.title),
      normalizeCourseName(course.originalName),
    }..remove('');
    var score = 0;
    for (final name in names) {
      if (name == wanted) {
        score = 3;
      } else if (score < 2 &&
          wanted.length >= 2 &&
          (name.startsWith(wanted) || wanted.startsWith(name))) {
        score = 2;
      } else if (score < 1 && wanted.length >= 2 && name.contains(wanted)) {
        score = 1;
      }
    }
    if (score == 0) continue;
    if (score > bestScore ||
        (score == bestScore &&
            course.semester.compareTo(best?.semester ?? '') > 0)) {
      best = course;
      bestScore = score;
    }
  }
  return best;
}
