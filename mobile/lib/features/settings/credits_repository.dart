import 'dart:convert';
import 'dart:io';
import '../academic_calendar/calendar_repository.dart';

class CreditsDocument {
  CreditsDocument._(
    this.revision,
    this.introduction,
    this.entries,
    this.canonical,
  );
  final int revision;
  final String introduction;
  final List<Map<String, dynamic>> entries;
  final String canonical;
  factory CreditsDocument.decode(List<int> bytes) {
    if (bytes.length > 131072) {
      throw const FormatException('Large credits document');
    }
    final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    bool text(dynamic v, int limit) =>
        v is String && v.trim().isNotEmpty && v.length <= limit;
    if (json['schemaVersion'] != 1 ||
        json['revision'] is! int ||
        json['revision'] < 1 ||
        !text(json['introduction'], 2000) ||
        json['entries'] is! List ||
        json['entries'].length > 100) {
      throw const FormatException('Invalid credits document');
    }
    final entries = (json['entries'] as List).cast<Map<String, dynamic>>();
    final ids = <String>{};
    for (final e in entries) {
      if (!text(e['id'], 100) ||
          !text(e['name'], 200) ||
          !text(e['description'], 2000) ||
          !text(e['projectName'], 200) ||
          !text(e['url'], 2048) ||
          e['order'] is! int ||
          !ids.add(e['id'] as String)) {
        throw const FormatException('Invalid credits entry');
      }
      final url = Uri.parse(e['url'] as String);
      if (url.scheme != 'https' ||
          url.host.isEmpty ||
          url.userInfo.isNotEmpty) {
        throw const FormatException('Invalid credits URL');
      }
    }
    entries.sort((a, b) {
      final order = (a['order'] as int).compareTo(b['order'] as int);
      return order == 0
          ? (a['id'] as String).compareTo(b['id'] as String)
          : order;
    });
    final canonical = jsonEncode({
      'revision': json['revision'],
      'introduction': json['introduction'],
      'entries': entries
          .map(
            (e) => {
              for (final key in [
                'id',
                'name',
                'description',
                'projectName',
                'url',
                'order',
              ])
                key: e[key],
            },
          )
          .toList(),
    });
    return CreditsDocument._(
      json['revision'] as int,
      json['introduction'] as String,
      List.unmodifiable(entries),
      canonical,
    );
  }
}

class CreditsSnapshot {
  const CreditsSnapshot(this.document, this.source, [this.message]);
  final CreditsDocument document;
  final String source;
  final String? message;
}

class CreditsRepository {
  CreditsRepository({this.cacheDirectory, CalendarFetch? fetch})
    : fetch = fetch ?? CachedCalendarRepository.download;
  final Directory? cacheDirectory;
  final CalendarFetch fetch;
  CreditsSnapshot? _current;
  Future<CreditsSnapshot>? _pending;
  static final url = Uri.parse(
    'https://raw.githubusercontent.com/windlessme/niu-app-android/main/app-content/credits.json',
  );
  // Same reviewed public content as app-content/credits.json; available offline.
  static const bundled =
      '''{"schemaVersion":1,"revision":3,"introduction":"感謝下列開源專案與開發者提供靈感與參考：","entries":[{"id":"qian403-niu-app","name":"qian403","description":"iOS NIU-app 開發者與維護者","projectName":"NIU-app","url":"https://github.com/qian403/NIU-app","order":5},{"id":"kennyyang0726-niu-app-ios","name":"KennyYang0726","description":"NIU_APP_IOS 開發者","projectName":"NIU_APP_IOS","url":"https://github.com/KennyYang0726/NIU_APP_IOS","order":10}]}''';

  Future<CreditsSnapshot> local() async {
    if (_current != null) return _current!;
    var result = CreditsSnapshot(
      CreditsDocument.decode(utf8.encode(bundled)),
      'App 內建名單',
    );
    try {
      if (cacheDirectory != null) {
        final cached = CreditsDocument.decode(
          await File('${cacheDirectory!.path}/credits.json').readAsBytes(),
        );
        if (cached.revision > result.document.revision) {
          result = CreditsSnapshot(cached, '本機快取');
        }
      }
    } catch (_) {
      /* Retain reviewed bundled content. */
    }
    return _current ??= result;
  }

  Future<CreditsSnapshot> refresh() =>
      _pending ??= _refresh().whenComplete(() => _pending = null);
  Future<CreditsSnapshot> _refresh() async {
    final previous = await local();
    try {
      final bytes = await fetch(url);
      final next = CreditsDocument.decode(bytes);
      final current = _current ?? previous;
      if (next.revision < current.document.revision ||
          (next.revision == current.document.revision &&
              next.canonical != current.document.canonical)) {
        throw const FormatException('Credits revision conflict');
      }
      String? notice;
      try {
        if (cacheDirectory != null) {
          await cacheDirectory!.create(recursive: true);
          final file = File('${cacheDirectory!.path}/credits.json.tmp');
          await file.writeAsBytes(bytes, flush: true);
          await file.rename('${cacheDirectory!.path}/credits.json');
        }
      } catch (_) {
        notice = '名單已更新，但無法儲存離線快取。';
      }
      return _current = CreditsSnapshot(next, 'GitHub 最新名單', notice);
    } catch (_) {
      return CreditsSnapshot(
        previous.document,
        previous.source,
        '暫時無法更新，顯示已儲存的公開名單。',
      );
    }
  }
}
