import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/features/academic_calendar/calendar_providers.dart';
import 'package:niu_mobile/features/academic_calendar/calendar_repository.dart';
import 'package:niu_mobile/features/academic_calendar/calendar_screen.dart';
import 'package:niu_mobile/shared/niu_theme.dart';

void main() {
  testWidgets(
    'calendar searches across months and exposes official event source',
    (tester) async {
      final data = await BundledCalendarRepository(rootBundle).load(115);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            calendarYearsProvider.overrideWith((ref) async => [115]),
            calendarProvider.overrideWith((ref, year) async => data),
          ],
          child: MaterialApp(
            theme: NiuTheme.light,
            home: const CalendarScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('月曆'), findsOneWidget);
      expect(find.text('今天'), findsOneWidget);
      await tester.enterText(find.byType(EditableText), '期中');
      await tester.pumpAndSettle();
      expect(find.text('搜尋結果'), findsOneWidget);
      final title = data.events.firstWhere((e) => e.title.contains('期中')).title;
      await tester.tap(find.text(title).first);
      await tester.pumpAndSettle();
      expect(find.text('校方原文'), findsOneWidget);
      expect(find.textContaining('查看校方 PDF'), findsOneWidget);
      Navigator.of(tester.element(find.text('校方原文'))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('清除搜尋'));
      await tester.pumpAndSettle();
      expect(find.text('搜尋結果'), findsNothing);
      expect(find.byTooltip('上個月'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
