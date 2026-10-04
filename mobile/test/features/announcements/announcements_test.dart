import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/features/announcements/announcement_board.dart';
import 'package:niu_mobile/features/announcements/announcement_repository.dart';
import 'package:niu_mobile/shared/shared.dart';
import 'package:shared_preferences/shared_preferences.dart';

List<int> doc(int revision, List<Map<String, dynamic>> items) => utf8.encode(
  jsonEncode({
    'schemaVersion': 1,
    'revision': revision,
    'announcements': items,
  }),
);

void main() {
  test('the published file is valid and the bundled copy is empty', () {
    // CI checks every edit to app-content/announcements.json.
    final published = AnnouncementDocument.decode(
      File('../app-content/announcements.json').readAsBytesSync(),
    );
    final bundled = AnnouncementDocument.decode(
      utf8.encode(AnnouncementRepository.bundled),
    );
    // Bundled notices would outlive their date on old installs.
    expect(bundled.announcements, isEmpty);
    expect(bundled.revision, lessThanOrEqualTo(published.revision));
  });

  test('documents are checked before use', () {
    final ok = AnnouncementDocument.decode(
      doc(2, [
        {
          'id': 'a',
          'title': '期中考週',
          'body': '請留意考試時間。',
          'level': 'warning',
          'popup': true,
          'start': '2026-10-01',
          'end': '2026-10-31',
          'url': 'https://example.org',
          'linkLabel': '看說明',
        },
      ]),
    );
    expect(ok.announcements.single.level, AnnouncementLevel.warning);
    for (final bad in [
      {'id': 'a', 'title': 't', 'body': 'b', 'url': 'http://x.org'},
      {'id': 'a', 'title': 't', 'body': 'b', 'start': '2026-02-30'},
      {
        'id': 'a',
        'title': 't',
        'body': 'b',
        'start': '2026-10-02',
        'end': '2026-10-01',
      },
      {'id': 'a', 'title': '', 'body': 'b'},
      {'id': 'a', 'title': 't', 'body': 'b', 'level': 'urgent'},
    ]) {
      expect(
        () => AnnouncementDocument.decode(doc(1, [bad])),
        throwsFormatException,
        reason: '$bad',
      );
    }
    expect(
      () => AnnouncementDocument.decode(
        doc(1, [
          {'id': 'a', 'title': 't', 'body': 'b'},
          {'id': 'a', 'title': 't', 'body': 'b'},
        ]),
      ),
      throwsFormatException,
    );
  });

  test('visibility follows Taipei dates and the app version', () {
    final a = Announcement(
      id: 'a',
      title: 't',
      body: 'b',
      start: DateTime(2026, 10, 5),
      end: DateTime(2026, 10, 6),
      maxVersion: '1.0.9',
    );
    // 2026-10-04 16:30 UTC is already 10/5 00:30 in Taipei.
    expect(a.visible(now: DateTime.utc(2026, 10, 4, 16, 30)), isTrue);
    expect(a.visible(now: DateTime.utc(2026, 10, 4, 15, 30)), isFalse);
    expect(a.visible(now: DateTime.utc(2026, 10, 6, 15, 59)), isTrue);
    expect(a.visible(now: DateTime.utc(2026, 10, 6, 16, 1)), isFalse);
    final day = DateTime.utc(2026, 10, 5, 4);
    expect(a.visible(now: day, version: '1.0.9'), isTrue);
    expect(a.visible(now: day, version: '1.0.10'), isFalse);
    expect(compareVersions('1.0.10', '1.0.9'), 1);
    expect(compareVersions('1.0', '1.0.0'), 0);
  });

  test('revisions only move forward and the cache survives', () async {
    final dir = await Directory.systemTemp.createTemp('announcements');
    addTearDown(() => dir.delete(recursive: true));
    var served = doc(3, [
      {'id': 'x', 'title': '新公告', 'body': '內容'},
    ]);
    final repo = AnnouncementRepository(
      cacheDirectory: dir,
      fetch: (_) async => served,
    );
    expect((await repo.local()).announcements, isEmpty);
    final now = DateTime(2026, 10, 5, 8);
    expect((await repo.refresh(now: now)).revision, 3);
    // Within an hour GitHub is not asked again.
    served = doc(4, []);
    expect(
      (await repo.refresh(now: now.add(const Duration(minutes: 30)))).revision,
      3,
    );
    // An older revision never replaces a newer one.
    served = doc(2, []);
    expect((await repo.refresh(force: true, now: now)).revision, 3);
    // A failed check keeps what was there.
    final offline = AnnouncementRepository(
      cacheDirectory: dir,
      fetch: (_) async => throw const SocketException('offline'),
    );
    final restored = await offline.refresh(force: true);
    expect(restored.revision, 3);
    expect(restored.announcements.single.title, '新公告');
  });

  testWidgets('home cards close for good; popups show only once', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final repo = AnnouncementRepository(
      fetch: (_) async => doc(2, [
        {'id': 'pop', 'title': '系統維護', 'body': '今晚暫停服務。', 'popup': true},
        {'id': 'old', 'title': '舊版提醒', 'body': '請更新。', 'maxVersion': '1.0.0'},
      ]),
    );
    Widget app() => MaterialApp(
      theme: NiuTheme.light,
      home: Scaffold(
        body: AnnouncementBoard(
          repository: Future.value(repo),
          version: Future.value('1.0.11'),
        ),
      ),
    );
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    // The dialog first; the version-limited notice is not for 1.0.11.
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();
    expect(find.text('系統維護'), findsOneWidget);
    expect(find.text('舊版提醒'), findsNothing);
    await tester.tap(find.byTooltip('關閉這則公告'));
    await tester.pumpAndSettle();
    expect(find.text('系統維護'), findsNothing);
    // Coming back: neither the dialog nor the closed card returns.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('系統維護'), findsNothing);
  });
}
