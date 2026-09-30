import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/features/settings/credits_repository.dart';

void main() {
  test('bundled credits match the published app-content file', () {
    final published = CreditsDocument.decode(
      File('../app-content/credits.json').readAsBytesSync(),
    );
    final bundled = CreditsDocument.decode(
      utf8.encode(CreditsRepository.bundled),
    );
    expect(bundled.canonical, published.canonical);
    expect(CreditsRepository.url.path, contains('windlessme/niu-app-android'));
  });

  test('credits validate public links and duplicate identities', () {
    final json = jsonDecode(CreditsRepository.bundled);
    json['entries'][0]['url'] = 'javascript:alert(1)';
    expect(
      () => CreditsDocument.decode(utf8.encode(jsonEncode(json))),
      throwsFormatException,
    );
    json['entries'][0]['url'] = 'https://github.com/example';
    json['entries'].add(json['entries'][0]);
    expect(
      () => CreditsDocument.decode(utf8.encode(jsonEncode(json))),
      throwsFormatException,
    );
  });

  test(
    'credits persist reviewed revisions and reject same-revision mutation',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'niu-credits-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final json = jsonDecode(CreditsRepository.bundled);
      json['revision'] = 2;
      final repository = CreditsRepository(
        cacheDirectory: directory,
        fetch: (_) async => utf8.encode(jsonEncode(json)),
      );
      expect((await repository.refresh()).document.revision, 2);
      json['introduction'] = 'Changed without revision';
      final rejected = await repository.refresh();
      expect(rejected.document.introduction, isNot('Changed without revision'));
      expect(rejected.message, isNotNull);
      final offline = CreditsRepository(
        cacheDirectory: directory,
        fetch: (_) async => throw const SocketException('offline'),
      );
      expect((await offline.refresh()).document.revision, 2);
      expect(
        await File('${directory.path}/credits.json.tmp').exists(),
        isFalse,
      );
    },
  );
}
