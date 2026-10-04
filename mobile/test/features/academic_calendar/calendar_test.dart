import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/core/time/campus_date.dart';
import 'package:niu_mobile/features/academic_calendar/calendar_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('academic year switches at Taipei August 1, not UTC midnight', () {
    expect(
      CampusDate.at(DateTime.parse('2027-07-31T15:59:59Z')).academicYear,
      115,
    );
    expect(
      CampusDate.at(DateTime.parse('2027-07-31T16:00:00Z')).academicYear,
      116,
    );
    expect(
      CampusDate.at(DateTime.parse('2026-12-31T16:00:00Z')).academicYear,
      115,
    );
    expect(() => CampusDate.parse('2026-02-30'), throwsFormatException);
  });

  test(
    'bundled snapshots match hashes and preserve inclusive intervals',
    () async {
      final repository = BundledCalendarRepository(rootBundle);
      expect(await repository.years(), [114, 115]);
      final previous = await repository.load(114);
      final current = await repository.load(115);
      expect(previous.events.length, 93);
      expect(current.events.length, 92);
      final exam = current.events.firstWhere((event) => event.title == '期末考試');
      expect(exam.start.toString(), '2026-12-21');
      expect(exam.end.toString(), '2027-01-10');
      await expectLater(repository.load(116), throwsStateError);
    },
  );
}
