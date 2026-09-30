import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/features/library/library_repository.dart';
import 'package:niu_mobile/features/library/library_screen.dart';
import 'package:niu_mobile/features/settings/settings_screen.dart';
import 'package:niu_mobile/features/attendance/attendance_screen.dart';
import 'package:niu_mobile/features/moodle/moodle_repository.dart';
import 'package:niu_mobile/shared/shared.dart';

class FailingLibrary extends LibraryRepository {
  FailingLibrary() : super(Dio(BaseOptions(baseUrl: 'https://sso.niu.edu.tw')));
  final requests = <LibraryCodeKind>[];
  @override
  Future<Uint8List> image(String account, LibraryCodeKind kind) async {
    requests.add(kind);
    throw const FormatException('offline');
  }
}

class UnusedMoodleRepository implements MoodleRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final dark in [false, true]) {
    Future<void> mount(WidgetTester tester, Widget child) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: dark ? NiuTheme.dark : NiuTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
              padding: const EdgeInsets.only(bottom: 24),
            ),
            child: child!,
          ),
          home: child,
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('settings theme choice remains usable at 320/2 dark=$dark', (
      tester,
    ) async {
      ThemeMode? selected;
      await mount(
        tester,
        SettingsScreen(onThemeModeChanged: (value) => selected = value),
      );
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('深色'));
      await tester.tap(find.text('深色'));
      await tester.pumpAndSettle();
      expect(selected, ThemeMode.dark);
      expect(tester.takeException(), isNull);
    });

    testWidgets('barcode failure and retry fit at 320/2 dark=$dark', (
      tester,
    ) async {
      final repository = FailingLibrary();
      await mount(
        tester,
        LibraryScreen(account: 'student', repository: repository),
      );
      await tester.tap(find.text('借書條碼'));
      await tester.pumpAndSettle();
      expect(repository.requests.last, LibraryCodeKind.borrowing);
      expect(find.textContaining('暫時無法取得圖碼'), findsOneWidget);
      final retry = find.widgetWithText(FilledButton, '重新整理');
      await tester.ensureVisible(retry);
      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(repository.requests.length, 3);
      expect(tester.getSize(retry).height, greaterThanOrEqualTo(48));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('scanner manual entry scrolls above keyboard dark=$dark', (
      tester,
    ) async {
      await mount(
        tester,
        AttendanceScannerScreen(repository: UnusedMoodleRepository()),
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.enterText(find.byType(TextField), 'invalid');
      await tester.pumpAndSettle();
      final button = find.widgetWithText(FilledButton, '開啟點名');
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.textContaining('無法開啟點名'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  }
}
