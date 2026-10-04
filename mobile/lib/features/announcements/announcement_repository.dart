import 'dart:convert';
import 'dart:io';
import '../../core/network/public_content.dart';

enum AnnouncementLevel { info, warning }

/// One notice from app-content/announcements.json.
class Announcement {
  const Announcement({
    required this.id,
    required this.title,
    required this.body,
    this.level = AnnouncementLevel.info,
    this.popup = false,
    this.start,
    this.end,
    this.url,
    this.linkLabel,
    this.minVersion,
    this.maxVersion,
  });
  final String id, title, body;
  final AnnouncementLevel level;

  /// Shown once as a dialog, besides the home card.
  final bool popup;

  /// Calendar days in Taipei, inclusive; null means open-ended.
  final DateTime? start, end;
  final Uri? url;
  final String? linkLabel;

  /// Only versions within this range see it, e.g. 「請更新」 for old builds.
  final String? minVersion, maxVersion;

  /// Whether a student on [version] should see it on [now].
  bool visible({required DateTime now, String? version}) {
    final taipei = now.toUtc().add(const Duration(hours: 8));
    final today = DateTime(taipei.year, taipei.month, taipei.day);
    if (start != null && today.isBefore(start!)) return false;
    if (end != null && today.isAfter(end!)) return false;
    if (version != null) {
      if (minVersion != null && compareVersions(version, minVersion!) < 0) {
        return false;
      }
      if (maxVersion != null && compareVersions(version, maxVersion!) > 0) {
        return false;
      }
    }
    return true;
  }
}

/// 1.0.9 < 1.0.10; missing parts count as 0.
int compareVersions(String a, String b) {
  List<int> parts(String v) => [
    for (final p in v.split(RegExp(r'[.+\s]')).take(3)) int.tryParse(p) ?? 0,
  ];
  final x = parts(a), y = parts(b);
  for (var i = 0; i < 3; i++) {
    final l = i < x.length ? x[i] : 0, r = i < y.length ? y[i] : 0;
    if (l != r) return l.compareTo(r);
  }
  return 0;
}

class AnnouncementDocument {
  AnnouncementDocument._(this.revision, this.announcements, this.canonical);
  final int revision;
  final List<Announcement> announcements;
  final String canonical;

  factory AnnouncementDocument.decode(List<int> bytes) {
    if (bytes.length > 131072) {
      throw const FormatException('Large announcements document');
    }
    final json = jsonDecode(utf8.decode(bytes));
    if (json is! Map ||
        json['schemaVersion'] != 1 ||
        json['revision'] is! int ||
        (json['revision'] as int) < 1 ||
        json['announcements'] is! List ||
        (json['announcements'] as List).length > 50) {
      throw const FormatException('Invalid announcements document');
    }
    bool text(Object? v, int limit) =>
        v is String && v.trim().isNotEmpty && v.length <= limit;
    bool optional(Object? v, int limit) => v == null || text(v, limit);
    DateTime? day(Object? v) {
      if (v == null) return null;
      final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch('$v');
      final date = m == null
          ? null
          : DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
      if (date == null || date.toIso8601String().substring(0, 10) != v) {
        throw const FormatException('Invalid announcement date');
      }
      return date;
    }

    final ids = <String>{};
    final result = <Announcement>[];
    for (final e in json['announcements'] as List) {
      if (e is! Map ||
          !text(e['id'], 100) ||
          !ids.add(e['id'] as String) ||
          !text(e['title'], 100) ||
          !text(e['body'], 2000) ||
          !const {null, 'info', 'warning'}.contains(e['level']) ||
          !const {null, true, false}.contains(e['popup']) ||
          !optional(e['url'], 2048) ||
          !optional(e['linkLabel'], 20) ||
          !optional(e['minVersion'], 20) ||
          !optional(e['maxVersion'], 20)) {
        throw const FormatException('Invalid announcement');
      }
      Uri? url;
      if (e['url'] != null) {
        url = Uri.parse(e['url'] as String);
        if (url.scheme != 'https' ||
            url.host.isEmpty ||
            url.userInfo.isNotEmpty) {
          throw const FormatException('Invalid announcement URL');
        }
      }
      final start = day(e['start']), end = day(e['end']);
      if (start != null && end != null && end.isBefore(start)) {
        throw const FormatException('Announcement ends before it starts');
      }
      result.add(
        Announcement(
          id: e['id'] as String,
          title: (e['title'] as String).trim(),
          body: (e['body'] as String).trim(),
          level: e['level'] == 'warning'
              ? AnnouncementLevel.warning
              : AnnouncementLevel.info,
          popup: e['popup'] == true,
          start: start,
          end: end,
          url: url,
          linkLabel: e['linkLabel'] as String?,
          minVersion: e['minVersion'] as String?,
          maxVersion: e['maxVersion'] as String?,
        ),
      );
    }
    return AnnouncementDocument._(
      json['revision'] as int,
      List.unmodifiable(result),
      jsonEncode({
        'schemaVersion': 1,
        'revision': json['revision'],
        'announcements': json['announcements'],
      }),
    );
  }
}

/// Reads announcements from GitHub raw, like the credits list: a bundled
/// copy for the first offline start, a verified cache, and revisions that
/// only move forward.
class AnnouncementRepository {
  AnnouncementRepository({this.cacheDirectory, PublicContentFetch? fetch})
    : fetch = fetch ?? fetchPublicContent;
  final Directory? cacheDirectory;
  final PublicContentFetch fetch;
  static final url = Uri.parse(
    'https://raw.githubusercontent.com/windlessme/niu-app-android/main/app-content/announcements.json',
  );

  /// Always empty: a notice built into the app would outlive its date on
  /// installs that never update.
  static const bundled = '{"schemaVersion":1,"revision":1,"announcements":[]}';

  /// Checking GitHub more often than this gains nothing.
  static const checkEvery = Duration(hours: 1);

  AnnouncementDocument? _current;
  DateTime? _checkedAt;
  Future<AnnouncementDocument>? _pending;

  File? get _file => cacheDirectory == null
      ? null
      : File('${cacheDirectory!.path}/announcements.json');

  Future<AnnouncementDocument> local() async {
    if (_current != null) return _current!;
    var result = AnnouncementDocument.decode(utf8.encode(bundled));
    try {
      final file = _file;
      if (file != null && await file.exists()) {
        final cached = AnnouncementDocument.decode(await file.readAsBytes());
        if (cached.revision >= result.revision) result = cached;
      }
    } catch (_) {
      /* A damaged cache falls back to the bundled copy. */
    }
    return _current ??= result;
  }

  /// The newest document; GitHub is asked at most once per [checkEvery]
  /// unless [force]. Failures keep what was already there.
  Future<AnnouncementDocument> refresh({bool force = false, DateTime? now}) {
    final at = now ?? DateTime.now();
    if (!force &&
        _checkedAt != null &&
        at.difference(_checkedAt!) < checkEvery &&
        _current != null) {
      return Future.value(_current!);
    }
    return _pending ??= _refresh(at).whenComplete(() => _pending = null);
  }

  Future<AnnouncementDocument> _refresh(DateTime at) async {
    final previous = await local();
    try {
      final next = AnnouncementDocument.decode(await fetch(url));
      _checkedAt = at;
      if (next.revision < previous.revision ||
          (next.revision == previous.revision &&
              next.canonical != previous.canonical)) {
        return previous;
      }
      _current = next;
      try {
        final file = _file;
        if (file != null) {
          await file.parent.create(recursive: true);
          final temp = File('${file.path}.tmp');
          await temp.writeAsBytes(utf8.encode(next.canonical), flush: true);
          await temp.rename(file.path);
        }
      } catch (_) {
        /* Shown now; cached next time. */
      }
      return next;
    } catch (_) {
      return previous;
    }
  }
}
