import 'package:html/parser.dart' as html;
import 'package:html/dom.dart' as dom;

/// A display-only view of the original Moodle payload.
class CoursePresentation {
  CoursePresentation(this.source);
  final Map<String, dynamic> source;

  static String text(Object? value) {
    if (value is! String && value is! num) return '';
    final fragment = html.parseFragment('$value');
    for (final node in fragment.querySelectorAll('br')) {
      node.replaceWith(html.parseFragment('\n'));
    }
    for (final node in fragment.querySelectorAll('p,div,tr,li')) {
      node.nodes.add(dom.Text('\n'));
    }
    return (fragment.text ?? '').replaceAll('\u00a0', ' ').trim();
  }

  String first(List<String> keys) {
    for (final key in keys) {
      final value = text(source[key]);
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  late final String summary = text(source['summary']);
  String field(List<String> labels) {
    // Only explicit, bounded metadata is eligible for compact cards. Never
    // infer a teacher or credits from an arbitrary syllabus sentence.
    final match = RegExp(
      '(?:^|[\\n;；])\\s*(?:${labels.map(RegExp.escape).join('|')})\\s*[:：]\\s*([^\\n;；]+)',
      multiLine: true,
    ).firstMatch(summary);
    return match?.group(1)?.trim() ?? '';
  }

  late final String code = first(['idnumber', 'shortname']);
  late final String semester = RegExp(r'^\d{4}(?=_)').stringMatch(code) ?? '';
  late final String originalName = first(['fullname', 'displayname']);
  late final String title = _title();
  String _title() {
    var name = first(['chinesename', 'name_zh', 'fullname', 'displayname']);
    // Strip only the exact supplied identifier, preserving meaningful brackets.
    if (code.isNotEmpty) {
      name = name.replaceFirst(
        RegExp('\\s*[（(]${RegExp.escape(code)}[)）]\\s*\$'),
        '',
      );
    }
    return name.isEmpty ? '未提供課程名稱' : name;
  }

  late final String englishName = first(['englishname', 'name_en']).isNotEmpty
      ? first(['englishname', 'name_en'])
      : field(['英文名稱', '英文課程名稱', '課程英文名稱']);
  late final String teacher = _teacher();
  String _teacher() {
    var value = first(['teacher', 'teachername']);
    if (value.isEmpty) value = field(['開課教師', '授課教師', '教師']);
    value = value.replaceAll(RegExp(r'[（(][^()（）]*@[^()（）]*[)）]'), '').trim();
    return value.isEmpty ? '教師未提供' : value;
  }

  late final String credits = _credits();
  String _credits() {
    var value = first(['credits', 'credit']);
    if (value.isEmpty) value = field(['學分數', '學分']);
    return value.isEmpty
        ? '學分未提供'
        : '$value${value.contains('學分') ? '' : ' 學分'}';
  }

  late final String searchText = '$title $englishName $code $teacher'
      .toLowerCase();
}
