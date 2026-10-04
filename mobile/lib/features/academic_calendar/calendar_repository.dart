import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

import '../../core/time/campus_date.dart';
import '../../core/network/public_content.dart';

class CalendarEvent {
  CalendarEvent.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      title = json['title'] as String,
      start = CampusDate.parse(json['startDate'] as String),
      end = CampusDate.parse(json['endDate'] as String),
      category = json['category'] as String,
      note = json['note'] as String?,
      sourceId = json['sourceId'] as String?,
      sourcePage = json['sourcePage'] as int?,
      sourceText = json['sourceText'] as String {
    if (end.compareTo(start) < 0) {
      throw const FormatException('Reversed event interval');
    }
  }

  final String id;
  final String title;
  final CampusDate start;
  final CampusDate end;
  final String category;
  final String? note;
  final String sourceText;
  final String? sourceId;
  final int? sourcePage;
  bool contains(CampusDate date) =>
      start.compareTo(date) <= 0 && end.compareTo(date) >= 0;
  bool boundary(CampusDate date) =>
      start.compareTo(date) == 0 || end.compareTo(date) == 0;
}

const calendarCategories = <String, String>{
  'registration': '選課',
  'exam': '考試',
  'holiday': '假期',
  'important': '重要日期',
  'semester': '學期',
  'activity': '活動',
  'deadline': '截止日期',
  'academic': '教務',
  'other': '其他',
};

/// A semester's teaching span, from the first class day to the semester end.
class CalendarSemester {
  const CalendarSemester(this.number, this.classesStart, this.end);
  final int number;
  final CampusDate classesStart, end;
}

class CalendarSnapshot {
  CalendarSnapshot(
    this.year,
    this.revision,
    List<CalendarEvent> events, {
    this.semesters = const [],
    this.sources = const {},
    this.sourceLabel = 'App 內建資料',
    this.message,
  }) : events = List.unmodifiable(events);
  final int year;
  final int revision;
  final List<CalendarEvent> events;
  final List<CalendarSemester> semesters;
  final Map<String, Uri> sources;
  final String sourceLabel;
  final String? message;
  CalendarSnapshot status(String label, [String? notice]) => CalendarSnapshot(
    year,
    revision,
    events,
    semesters: semesters,
    sources: sources,
    sourceLabel: label,
    message: notice,
  );
}

abstract class CalendarRepository {
  Future<List<int>> years();
  Future<CalendarSnapshot> load(int year);
}

class BundledCalendarRepository implements CalendarRepository {
  BundledCalendarRepository(this.bundle);
  final AssetBundle bundle;
  static const base = 'assets/academic_calendar';

  Future<List<Map<String, dynamic>>> _index() async {
    final json =
        jsonDecode(await bundle.loadString('$base/index.json'))
            as Map<String, dynamic>;
    if (json['schemaVersion'] != 1) {
      throw const FormatException('Unsupported calendar index');
    }
    return (json['calendars'] as List).cast<Map<String, dynamic>>();
  }

  @override
  Future<List<int>> years() async =>
      (await _index()).map((entry) => entry['academicYear'] as int).toList();

  @override
  Future<CalendarSnapshot> load(int year) async {
    final entry = (await _index()).firstWhere(
      (entry) => entry['academicYear'] == year,
      orElse: () => throw StateError('沒有此學年度的內建資料'),
    );
    if (entry['path'] != 'years/$year.json') {
      throw const FormatException('Unexpected calendar path');
    }
    final bytes = await bundle.load('$base/${entry['path']}');
    final data = bytes.buffer.asUint8List(
      bytes.offsetInBytes,
      bytes.lengthInBytes,
    );
    return decodeCalendar(data, entry);
  }
}

CalendarSnapshot decodeCalendar(List<int> data, Map<String, dynamic> entry) {
  final year = entry['academicYear'] as int;
  if (data.length > 2097152 ||
      entry['path'] != 'years/$year.json' ||
      sha256.convert(data).toString() != entry['sha256']) {
    throw const FormatException('Calendar hash mismatch');
  }
  final json = jsonDecode(utf8.decode(data)) as Map<String, dynamic>;
  if (json['schemaVersion'] != 1 ||
      json['academicYear'] != year ||
      json['revision'] != entry['revision'] ||
      json['timeZone'] != 'Asia/Taipei') {
    throw const FormatException('Calendar metadata mismatch');
  }
  final events = (json['events'] as List)
      .map((event) => CalendarEvent.fromJson(event as Map<String, dynamic>))
      .toList();
  if (json['revision'] is! int ||
      (json['revision'] as int) < 1 ||
      events.length > 10000 ||
      events.any(
        (e) =>
            e.id.isEmpty ||
            e.title.trim().isEmpty ||
            !calendarCategories.containsKey(e.category),
      )) {
    throw const FormatException('Invalid calendar content');
  }
  final start = CampusDate.parse(json['startDate'] as String);
  final end = CampusDate.parse(json['endDate'] as String);
  if (start.toString() != '${year + 1911}-08-01' ||
      end.toString() != '${year + 1912}-07-31') {
    throw const FormatException('Unexpected academic year boundaries');
  }
  final sources = {
    for (final source in json['sources'] as List)
      (source as Map<String, dynamic>)['id']: source['pageCount'] as int,
  };
  final urls = <String, Uri>{};
  for (final source in json['sources'] as List) {
    final url = Uri.parse(source['url'] as String);
    if (url.scheme != 'https' ||
        url.userInfo.isNotEmpty ||
        !(url.host == 'niu.edu.tw' || url.host.endsWith('.niu.edu.tw')) ||
        urls.containsKey(source['id'])) {
      throw const FormatException('Invalid calendar source');
    }
    urls[source['id'] as String] = url;
  }
  for (final raw in json['events'] as List) {
    final pageCount = sources[raw['sourceId']];
    final page = raw['sourcePage'];
    if (pageCount == null || page is! int || page < 1 || page > pageCount) {
      throw const FormatException('Unknown event source');
    }
  }
  if (events.any(
    (event) => event.start.compareTo(start) < 0 || event.end.compareTo(end) > 0,
  )) {
    throw const FormatException('Event outside academic year');
  }
  if (events.map((event) => event.id).toSet().length != events.length) {
    throw const FormatException('Duplicate calendar event');
  }
  events.sort((a, b) => a.start.compareTo(b.start));
  final semesters = <CalendarSemester>[];
  for (final raw in json['semesters'] as List? ?? const []) {
    final semester = raw as Map<String, dynamic>;
    final classes = CampusDate.parse(semester['classesStartDate'] as String);
    final last = CampusDate.parse(semester['endDate'] as String);
    if (classes.compareTo(start) < 0 ||
        last.compareTo(end) > 0 ||
        last.compareTo(classes) < 0) {
      throw const FormatException('Semester outside academic year');
    }
    semesters.add(CalendarSemester(semester['number'] as int, classes, last));
  }
  return CalendarSnapshot(
    year,
    json['revision'] as int,
    events,
    semesters: semesters,
    sources: Map.unmodifiable(urls),
  );
}

/// Serializes commits, keeping the index and its verified payload in one atomic
/// envelope. A delayed response can never replace a newer revision.
class CachedCalendarRepository implements CalendarRepository {
  CachedCalendarRepository({
    required AssetBundle bundle,
    required this.cacheDirectory,
    PublicContentFetch? fetch,
  }) : bundled = BundledCalendarRepository(bundle),
       fetch = fetch ?? fetchPublicContent;
  final BundledCalendarRepository bundled;
  final Directory cacheDirectory;
  final PublicContentFetch fetch;
  static final baseUrl = Uri.parse(
    'https://raw.githubusercontent.com/qian403/NIU-app/main/calendar-data/',
  );
  final _memory = <int, CalendarSnapshot>{};
  final _hashes = <int, String>{};
  final _pending = <int, Future<CalendarSnapshot>>{};
  Future<void> _commit = Future.value();

  Future<List<Map<String, dynamic>>> _remoteIndex() async {
    final bytes = await fetch(baseUrl.resolve('index.json'));
    if (bytes.length > 131072) throw const FormatException('Large index');
    final value = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    if (value['schemaVersion'] != 1) {
      throw const FormatException('Index version');
    }
    final entries = (value['calendars'] as List).cast<Map<String, dynamic>>();
    final years = <int>{};
    for (final e in entries) {
      final year = e['academicYear'];
      if (year is! int ||
          year < 1 ||
          year > 999 ||
          !years.add(year) ||
          e['revision'] is! int ||
          (e['revision'] as int) < 1 ||
          e['path'] != 'years/$year.json' ||
          e['sha256'] is! String ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(e['sha256'] as String)) {
        throw const FormatException('Invalid index entry');
      }
    }
    return entries;
  }

  @override
  Future<List<int>> years() async {
    final values = <int>{...await bundled.years()};
    try {
      if (await cacheDirectory.exists()) {
        await for (final f in cacheDirectory.list()) {
          final match = RegExp(r'calendar-(\d+)\.json$').firstMatch(f.path);
          if (match != null) values.add(int.parse(match[1]!));
        }
      }
      values.addAll(
        (await _remoteIndex()).map((e) => e['academicYear'] as int),
      );
    } catch (_) {
      /* Local years remain usable offline. */
    }
    return values.toList()..sort((a, b) => b.compareTo(a));
  }

  @override
  Future<CalendarSnapshot> load(int year) => _pending.putIfAbsent(
    year,
    () => _load(year).whenComplete(() {
      _pending.remove(year);
    }),
  );

  Future<CalendarSnapshot> _load(int year) async {
    CalendarSnapshot? local = _memory[year];
    if (local == null) {
      try {
        local = await bundled.load(year);
        final entry = (await bundled._index()).firstWhere(
          (e) => e['academicYear'] == year,
        );
        _hashes[year] = entry['sha256'] as String;
      } catch (_) {
        /* A future year may only exist remotely. */
      }
      try {
        final envelope = jsonDecode(
          await File(
            '${cacheDirectory.path}/calendar-$year.json',
          ).readAsString(),
        );
        final entry = Map<String, dynamic>.from(envelope['entry'] as Map);
        if (entry['academicYear'] != year) {
          throw const FormatException('Cache year');
        }
        final candidate = decodeCalendar(
          base64Decode(envelope['payload'] as String),
          entry,
        );
        if (local == null || candidate.revision > local.revision) {
          local = candidate.status('本機快取');
          _hashes[year] = entry['sha256'] as String;
        }
      } catch (_) {
        /* Corrupt caches never displace bundled data. */
      }
      if (local != null) _memory[year] = local;
    }
    try {
      final entry = (await _remoteIndex()).firstWhere(
        (e) => e['academicYear'] == year,
      );
      final bytes = await fetch(baseUrl.resolve(entry['path'] as String));
      final incoming = decodeCalendar(bytes, entry);
      late CalendarSnapshot result;
      final operation = _commit.then((_) async {
        final current = _memory[year];
        if (current != null &&
            (incoming.revision < current.revision ||
                (incoming.revision == current.revision &&
                    _hashes[year] != entry['sha256']))) {
          throw const FormatException('Calendar revision conflict');
        }
        String? message;
        try {
          await cacheDirectory.create(recursive: true);
          final target = '${cacheDirectory.path}/calendar-$year.json';
          final temporary = File('$target.tmp');
          await temporary.writeAsString(
            jsonEncode({'entry': entry, 'payload': base64Encode(bytes)}),
            flush: true,
          );
          await temporary.rename(target);
        } catch (_) {
          message = '資料已更新，但無法儲存離線快取。';
        }
        result = incoming.status('GitHub 最新資料', message);
        _memory[year] = result;
        _hashes[year] = entry['sha256'] as String;
      });
      _commit = operation.then<void>(
        (_) {},
        onError: (Object _, StackTrace _) {},
      );
      await operation;
      return result;
    } catch (_) {
      if (local != null) {
        return local.status(local.sourceLabel, '暫時無法確認更新，顯示已驗證的離線資料。');
      }
      rethrow;
    }
  }
}
