import 'moodle_repository.dart';
import 'course_presentation.dart';
import '../../shared/shared.dart';

/// Formats Moodle week headings without changing unrecognised section names.
String courseDateRange(String value) {
  final match = RegExp(
    r'^\s*(\d{1,2})\s*[月/]\s*(\d{1,2})\s*日?\s*[-–~～至]\s*(\d{1,2})\s*[月/]\s*(\d{1,2})\s*日?\s*$',
  ).firstMatch(value);
  if (match == null) return value;
  final parts = [for (var i = 1; i <= 4; i++) int.parse(match.group(i)!)];
  if (parts[0] < 1 ||
      parts[0] > 12 ||
      parts[2] < 1 ||
      parts[2] > 12 ||
      parts[1] < 1 ||
      parts[1] > 31 ||
      parts[3] < 1 ||
      parts[3] > 31) {
    return value;
  }
  return '${parts[0]} 月 ${parts[1]} 日 – ${parts[2]} 月 ${parts[3]} 日';
}

class CourseDetailSection {
  const CourseDetailSection(this.title, this.body);
  final String title, body;
}

List<CourseDetailSection> courseDetailSections(CoursePresentation course) {
  const labels = {
    '授課目的': '授課目的',
    '課程宗旨': '授課目的',
    '成績計算方式': '成績計算',
    '成績計算': '成績計算',
    '教學目標': '教學目標',
    '課程目標': '教學目標',
    '教學目的': '教學目標',
    '課程內容': '課程內容',
    '教學內容': '課程內容',
    '評分方式': '評分方式',
    '成績評量': '評分方式',
    '評量方式': '評分方式',
    '課程說明': '課程說明',
    '參考書目': '參考書目',
    '教科書': '教科書',
  };
  final sections = <CourseDetailSection>[];
  var title = '課程說明';
  var lines = <String>[];
  void flush() {
    final body = lines.join('\n').trim();
    if (body.isNotEmpty && !sections.any((s) => s.body == body)) {
      sections.add(CourseDetailSection(title, body));
    }
    lines = [];
  }

  final metadata = <String, List<String>>{
    '課程名稱': [course.title, course.originalName],
    '英文名稱': [course.englishName],
    '英文課程名稱': [course.englishName],
    '課程英文名稱': [course.englishName],
    '課程代碼': [course.code],
    '開課教師': [course.teacher],
    '授課教師': [course.teacher],
    '教師': [course.teacher],
    '學分': [course.credits, course.credits.replaceFirst(' 學分', '')],
    '學分數': [course.credits, course.credits.replaceFirst(' 學分', '')],
  };
  final summary = course.summary.replaceAllMapped(
    RegExp(
      r'[;；]\s*(?=(?:英文名稱|英文課程名稱|課程英文名稱|課程代碼|開課教師|授課教師|教師|學分數|學分|授課目的|課程宗旨|成績計算方式|成績計算|課程內容|評分方式)\s*[:：])',
    ),
    (_) => '\n',
  );
  for (final line in summary.split('\n')) {
    final match = RegExp(r'^\s*([^:：]+)\s*[:：]\s*(.*)$').firstMatch(line);
    final label = match?.group(1)?.trim() ?? line.trim();
    final value = match?.group(2)?.trim() ?? '';
    final comparable = value
        .replaceAll(RegExp(r'[（(][^()（）]*@[^()（）]*[)）]'), '')
        .replaceFirst(RegExp(r'[;；]\s*$'), '')
        .trim();
    if (match != null && (metadata[label]?.contains(comparable) ?? false)) {
      continue;
    }
    if (labels.containsKey(label)) {
      flush();
      title = labels[label]!;
      if (value.isNotEmpty) lines.add(value);
    } else {
      lines.add(line);
    }
  }
  flush();
  for (final entry in {
    'purpose': '教學目標',
    'content': '課程內容',
    'grading': '評分方式',
    'description': '課程說明',
  }.entries) {
    title = entry.value;
    lines = [CoursePresentation.text(course.source[entry.key])];
    flush();
  }
  final fields = course.source['customfields'];
  if (fields is List) {
    for (final field in fields.whereType<Map>()) {
      title = CoursePresentation.text(field['name']);
      final value = CoursePresentation.text(field['value']);
      if (metadata[title]?.contains(value) ?? false) continue;
      lines = [value];
      flush();
    }
  }
  return sections;
}

String submissionLabel(Object? status) => switch (status) {
  'submitted' => '已繳交',
  'draft' => '草稿',
  'new' => '未繳交',
  'reopened' => '重新開放繳交',
  null || '' => '繳交狀態未提供',
  _ => CoursePresentation.text(status),
};

List<Map<String, dynamic>> sortCourseAssignments(
  List<Map<String, dynamic>> values,
) {
  int due(Map<String, dynamic> value) {
    final date = int.tryParse('${value['duedate']}') ?? 0;
    return date > 0 ? date : 0x7fffffffffffffff;
  }

  final indexed = values.indexed.toList()
    ..sort((a, b) {
      final order = due(a.$2).compareTo(due(b.$2));
      return order == 0 ? a.$1.compareTo(b.$1) : order;
    });
  return indexed.map((entry) => entry.$2).toList();
}

NiuTone submissionTone(Object? status) => switch (status) {
  'submitted' => NiuTone.success,
  'draft' => NiuTone.warning,
  'new' || 'reopened' => NiuTone.accent,
  _ => NiuTone.neutral,
};

String gradeValue(Object? value) {
  final text = plain(value).trim();
  return text.isEmpty || text == '-' || text == '—' ? '未提供' : text;
}
