import 'dart:async';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/features/library/library_repository.dart';
import 'package:niu_mobile/features/library/library_screen.dart';
import 'package:niu_mobile/shared/niu_theme.dart';
import 'package:niu_mobile/shared/clock_format.dart';

class FakeLibrary extends LibraryRepository {
  FakeLibrary() : super(Dio(BaseOptions(baseUrl: 'https://sso.niu.edu.tw')));
  final requests = <Completer<Uint8List>>[];
  final kinds = <LibraryCodeKind>[];
  @override
  Future<Uint8List> image(String account, LibraryCodeKind kind) {
    kinds.add(kind);
    final request = Completer<Uint8List>();
    requests.add(request);
    return request.future;
  }
}

late Uint8List png;

void main() {
  setUpAll(() async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(Colors.white, BlendMode.src);
    final picture = recorder.endRecording();
    final image = await picture.toImage(10, 10);
    png = (await image.toByteData(
      format: ui.ImageByteFormat.png,
    ))!.buffer.asUint8List();
    image.dispose();
    picture.dispose();
  });
  test('clock is always Taipei 24-hour', () {
    expect(formatTaipeiClock(DateTime.utc(2026, 1, 1, 6, 3)), '14:03');
  });
  for (final dark in [false, true]) {
    testWidgets(
      '320px 2x ${dark ? 'dark' : 'light'} loading/error remains scrollable',
      (tester) async {
        tester.view.physicalSize = const Size(320, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repo = FakeLibrary();
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? NiuTheme.dark : NiuTheme.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: LibraryScreen(account: 'student', repository: repo),
          ),
        );
        await tester.pump();
        expect(
          tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNull,
        );
        repo.requests.single.completeError(
          const FormatException('missing data'),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('暫時無法取得圖碼'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets(
    'single flight queues latest kind and account; invalid responses never display',
    (tester) async {
      final repo = FakeLibrary();
      Widget app(String account) => MaterialApp(
        home: LibraryScreen(account: account, repository: repo),
      );
      await tester.pumpWidget(app('a'));
      await tester.pump();
      await tester.tap(find.text('借書條碼'));
      await tester.pump();
      await tester.pumpWidget(app('b'));
      expect(repo.requests.length, 1);
      repo.requests.first.complete(png);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(repo.requests.length, 2);
      expect(repo.kinds.last, LibraryCodeKind.borrowing);
      expect(find.byType(Image), findsNothing);
      repo.requests.last.completeError(const FormatException('missing'));
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'failed refresh retains only a young same-day image and expires at midnight',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = FakeLibrary();
      var now = DateTime.utc(2026, 1, 1, 15, 59);
      await tester.pumpWidget(
        MaterialApp(
          home: LibraryScreen(account: 'a', repository: repo, now: () => now),
        ),
      );
      await tester.pump();
      await tester.runAsync(() async {
        repo.requests.single.complete(png);
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const ValueKey('library-code-surface'))),
        const Size(420, 420),
      );
      await tester.scrollUntilVisible(find.text('重新整理'), 100);
      await tester.tap(find.text('重新整理'));
      await tester.pump();
      repo.requests.last.completeError(Exception('offline'));
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);
      expect(find.textContaining('目前的圖碼仍有效'), findsOneWidget);
      now = DateTime.utc(2026, 1, 1, 16);
      await tester.pump(const Duration(minutes: 1));
      expect(find.byType(Image), findsNothing);
      repo.requests.last.completeError(Exception('offline'));
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'cover and resume clear the code and revalidate without overlapping',
    (tester) async {
      final repo = FakeLibrary();
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          navigatorObservers: [libraryRouteObserver],
          home: LibraryScreen(account: 'a', repository: repo),
        ),
      );
      await tester.pump();
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('cover')),
        ),
      );
      await tester.pumpAndSettle();
      repo.requests.first.completeError(Exception('offline'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(minutes: 6));
      expect(repo.requests.length, 1);
      navigator.currentState!.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(repo.requests.length, 2);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(repo.requests.length, 2);
      repo.requests.last.completeError(Exception('offline'));
      await tester.pump();
      expect(repo.requests.length, 3);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
