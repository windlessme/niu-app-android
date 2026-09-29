import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/features/academic_calendar/calendar_repository.dart';

class FileBundle extends CachingAssetBundle {
  @override
  Future<String> loadString(String key, {bool cache = true}) =>
      File(key).readAsString();
  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(await File(key).readAsBytes());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final rootBundle = FileBundle();
  late Directory directory;
  late Map<String, dynamic> document;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('niu-calendar-test-');
    document =
        jsonDecode(
              await rootBundle.loadString(
                'assets/academic_calendar/years/115.json',
              ),
            )
            as Map<String, dynamic>;
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });

  CalendarFetch feed(Map<String, dynamic> value) {
    final bytes = utf8.encode(jsonEncode(value));
    final index = utf8.encode(
      jsonEncode({
        'schemaVersion': 1,
        'calendars': [
          {
            'academicYear': 115,
            'revision': value['revision'],
            'path': 'years/115.json',
            'sha256': sha256.convert(bytes).toString(),
          },
        ],
      }),
    );
    return (url) async => url.path.endsWith('index.json') ? index : bytes;
  }

  test(
    'atomic verified cache survives offline restart and rejects rollback',
    () async {
      document['revision'] = 3;
      final repository = CachedCalendarRepository(
        bundle: rootBundle,
        cacheDirectory: directory,
        fetch: feed(document),
      );
      expect((await repository.load(115)).revision, 3);
      expect(
        await File('${directory.path}/calendar-115.json.tmp').exists(),
        isFalse,
      );
      document['revision'] = 2;
      final restarted = CachedCalendarRepository(
        bundle: rootBundle,
        cacheDirectory: directory,
        fetch: feed(document),
      );
      final snapshot = await restarted.load(115);
      expect(snapshot.revision, 3);
      expect(snapshot.message, isNotNull);
      final offline = CachedCalendarRepository(
        bundle: rootBundle,
        cacheDirectory: directory,
        fetch: (_) async => throw const SocketException('offline'),
      );
      expect((await offline.load(115)).revision, 3);
    },
  );

  test(
    'same-revision altered payload never replaces reviewed bundle',
    () async {
      (document['events'] as List).first['title'] = 'altered';
      final repository = CachedCalendarRepository(
        bundle: rootBundle,
        cacheDirectory: directory,
        fetch: feed(document),
      );
      final snapshot = await repository.load(115);
      expect(snapshot.events.first.title, isNot('altered'));
      expect(snapshot.message, isNotNull);
      expect(
        await File('${directory.path}/calendar-115.json').exists(),
        isFalse,
      );
    },
  );

  test(
    'concurrent callers share refresh, preventing out-of-order commits',
    () async {
      document['revision'] = 2;
      final fetch = feed(document);
      final gate = Completer<void>();
      var requests = 0;
      final repository = CachedCalendarRepository(
        bundle: rootBundle,
        cacheDirectory: directory,
        fetch: (url) async {
          requests++;
          await gate.future;
          return fetch(url);
        },
      );
      final first = repository.load(115);
      final second = repository.load(115);
      expect(identical(first, second), isTrue);
      gate.complete();
      expect((await first).revision, 2);
      expect((await second).revision, 2);
      expect(requests, 2);
    },
  );

  test(
    'valid hash cannot admit foreign PDF sources or unknown categories',
    () async {
      document['revision'] = 2;
      (document['sources'] as List).first['url'] =
          'https://example.com/calendar.pdf';
      var repository = CachedCalendarRepository(
        bundle: rootBundle,
        cacheDirectory: directory,
        fetch: feed(document),
      );
      expect((await repository.load(115)).revision, 1);
      document =
          jsonDecode(
                await rootBundle.loadString(
                  'assets/academic_calendar/years/115.json',
                ),
              )
              as Map<String, dynamic>;
      document['revision'] = 2;
      (document['events'] as List).first['category'] = 'unreviewed';
      repository = CachedCalendarRepository(
        bundle: rootBundle,
        cacheDirectory: directory,
        fetch: feed(document),
      );
      expect((await repository.load(115)).revision, 1);
    },
  );
}
