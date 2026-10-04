/// One 多元認證 entry, e.g. 「專業進取（已認證，3 小時）」.
class EventCredit {
  const EventCredit(this.category, this.hours);
  final String category;

  /// 「3 小時」, or empty when the school gives no hours.
  final String hours;

  String get label =>
      [category, hours].where((part) => part.isNotEmpty).join('　');

  static final _entry = RegExp(r'([^（(、，,；;\n]*?)\s*[（(]([^）)]*)[）)]');
  static final _hours = RegExp(r'(\d+(?:\.\d+)?)\s*(?:小時|hrs?|h)');

  static String _hoursIn(String text) {
    final match = _hours.firstMatch(text);
    return match == null ? '' : '${match[1]} 小時';
  }

  static List<EventCredit> parse(String raw) {
    final text = raw.trim();
    if (text.isEmpty || text == '-' || text == '無') return const [];
    final entries = _entry.allMatches(text).toList();
    if (entries.isEmpty) {
      final hours = _hoursIn(text);
      final category = text
          .replaceAll(_hours, '')
          .replaceAll(RegExp(r'^認證\s*|[：:、，,\s]+$'), '')
          .trim();
      return [EventCredit(category, hours)];
    }
    return [
      for (final m in entries)
        EventCredit(
          m[1]!.replaceAll(RegExp(r'^[\s、，,；;]+|^認證\s*'), '').trim(),
          _hoursIn(m[2]!),
        ),
    ];
  }
}

class CampusEvent {
  CampusEvent.fromJson(Map<String, dynamic> json)
    : id = json['id']?.toString() ?? '',
      name = json['name']?.toString() ?? '',
      department = json['department']?.toString() ?? '',
      status = json['status']?.toString() ?? '',
      time = json['time']?.toString() ?? '',
      location = json['location']?.toString() ?? '',
      details = json['details']?.toString() ?? '',
      registration = json['registration']?.toString() ?? '',
      contact = json['contact']?.toString() ?? '',
      remark = json['remark']?.toString() ?? '',
      hours = json['hours']?.toString() ?? '',
      action = json['action']?.toString() ?? '',
      targets = json['targets']?.toString() ?? '',
      people = json['people']?.toString() ?? '';
  final String action, targets;

  /// Parsed 多元認證 categories and hours.
  late final List<EventCredit> credits = EventCredit.parse(hours);
  bool get canApply =>
      id.isNotEmpty &&
      !status.contains('已結束') &&
      !status.contains('截止') &&
      (targets.isEmpty || targets.contains('本校在校生'));
  final String id,
      name,
      department,
      status,
      time,
      location,
      details,
      registration,
      contact,
      remark,
      hours,
      people;

  /// Search across the number and the visible text. 「#123」 or 「No.123」
  /// match the number too.
  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    final number = q.replaceFirst(RegExp(r'^(#|no\.?\s*|編號\s*)'), '');
    if (id.isNotEmpty &&
        number.isNotEmpty &&
        id.toLowerCase().contains(number)) {
      return true;
    }
    return [
      name,
      department,
      location,
      details,
    ].any((value) => value.toLowerCase().contains(q));
  }

  /// Only public event fields, never the student's registration data.
  String get shareText {
    final lines = [name];
    for (final (label, value) in [
      ('活動編號', id),
      ('主辦單位', department),
      ('活動時間', time),
      ('活動地點', location),
      ('報名時間', registration),
    ]) {
      if (value.trim().isNotEmpty) lines.add('$label：${value.trim()}');
    }
    if (RegExp(r'^\d+$').hasMatch(id)) {
      lines.add('活動連結：https://ccsys.niu.edu.tw/MvcTeam/Act/Apply/$id');
    }
    return lines.join('\n');
  }

  Uri actionUri({required bool applied}) {
    final link = Uri.tryParse(action);
    if (link != null &&
        link.scheme == 'https' &&
        link.host == 'ccsys.niu.edu.tw' &&
        link.userInfo.isEmpty &&
        link.port == 443 &&
        link.path.startsWith(
          applied ? '/MvcTeam/Act/RegData/' : '/MvcTeam/Act/Apply/',
        )) {
      return link;
    }
    return Uri.https(
      'ccsys.niu.edu.tw',
      '/MvcTeam/Act/${applied ? 'RegData' : 'Apply'}/$id',
    );
  }
}
