import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/app/app.dart';
import 'package:niu_mobile/app/providers.dart';
import 'package:niu_mobile/features/academic_calendar/calendar_repository.dart';
import 'package:niu_mobile/features/home/home_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FixtureCalendarRepository implements CalendarRepository {
  @override
  Future<List<int>> years() async => [114, 115];
  @override
  Future<CalendarSnapshot> load(int year) async => CalendarSnapshot(year, 1, [
    CalendarEvent.fromJson({
      'id': 'fixture',
      'title': '測試事項',
      'startDate': '2026-09-28',
      'endDate': '2026-09-28',
      'category': 'academic',
      'note': null,
      'sourceText': '測試校方原文',
    }),
  ]);
}

void main() {
  testWidgets('calendar navigation uses injectable data and can search', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          calendarRepositoryProvider.overrideWithValue(
            FixtureCalendarRepository(),
          ),
        ],
        child: const NiuApp(),
      ),
    );
    await tester.pumpAndSettle();
    // Scroll the home page, not the tab pager around it.
    await tester.scrollUntilVisible(
      find.text('行事曆'),
      200,
      scrollable: find
          .descendant(
            of: find.byType(CampusHomeScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.ensureVisible(find.text('行事曆'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('行事曆'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText), '測試事項');
    await tester.pumpAndSettle();
    expect(find.text('測試事項', findRichText: false).last, findsOneWidget);
    await tester.enterText(find.byType(EditableText), '找不到的字串');
    await tester.pump();
    expect(find.text('測試事項'), findsNothing);
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.text('校園服務'), findsOneWidget);
  });
}
