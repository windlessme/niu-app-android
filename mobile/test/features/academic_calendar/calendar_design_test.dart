import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/features/academic_calendar/calendar_providers.dart';
import 'package:niu_mobile/core/time/campus_date.dart';
import 'package:niu_mobile/features/academic_calendar/calendar_repository.dart';
import 'package:niu_mobile/features/academic_calendar/calendar_screen.dart';
import 'package:niu_mobile/shared/shared.dart';

void main() {
  for (final dark in [false, true]) {
    for (final width in [320.0, 600.0]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('calendar dark=$dark width=$width scale=$scale', (
          tester,
        ) async {
          tester.view.physicalSize = Size(width, 1200);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final today = CampusDate.at(DateTime.now());
          final date = today.toString();
          final data = CalendarSnapshot(today.academicYear, 1, [
            for (var i = 0; i < 4; i++)
              CalendarEvent.fromJson({
                'id': '$i',
                'title': '今日事件 $i',
                'startDate': date,
                'endDate': date,
                'category': 'exam',
                'sourceText': '校方公告',
              }),
            CalendarEvent.fromJson({
              'id': 'ongoing',
              'title': '期間事項',
              'startDate': CampusDate(today.year, today.month, 1).toString(),
              'endDate': CampusDate(
                today.year,
                today.month,
                DateTime.utc(today.year, today.month + 1, 0).day,
              ).toString(),
              'category': 'registration',
              'sourceText': '校方公告',
            }),
          ]);
          final semantics = tester.ensureSemantics();
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                calendarYearsProvider.overrideWith(
                  (ref) async => [today.academicYear],
                ),
                calendarProvider.overrideWith((ref, year) async => data),
              ],
              child: MaterialApp(
                theme: dark ? NiuTheme.dark : NiuTheme.light,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(scale),
                    disableAnimations: true,
                  ),
                  child: child!,
                ),
                home: const CalendarScreen(),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final day = find.byWidgetPredicate(
            (widget) =>
                widget is Semantics &&
                (widget.properties.label?.startsWith('$date，今天') ?? false),
          );
          await tester.ensureVisible(day);
          await tester.pumpAndSettle();
          expect(day, findsOneWidget);
          final widget = tester.widget<Semantics>(day);
          expect(widget.properties.label, contains('個當日事項'));
          expect(widget.properties.label, contains('個期間進行中'));
          expect(tester.getSize(day).width, greaterThanOrEqualTo(48));
          expect(tester.getSize(day).height, greaterThanOrEqualTo(48));
          expect(tester.takeException(), isNull);
          semantics.dispose();
        });
      }
    }
  }
}
