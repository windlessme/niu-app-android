import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/features/moodle/moodle_demo.dart';
import 'package:niu_mobile/features/moodle/moodle_page_screen.dart';
import 'package:niu_mobile/features/moodle/moodle_upcoming.dart';

DateTime taipei(int y, int m, int d, [int h = 0, int min = 0]) =>
    DateTime.utc(y, m, d, h - 8, min);

void main() {
  // Wednesday 2026-10-07 10:00 in Taipei.
  final now = taipei(2026, 10, 7, 10);

  test('window keeps seven days back and two weeks ahead', () {
    expect(UpcomingRules.inWindow(taipei(2026, 9, 30, 11), now), isTrue);
    expect(UpcomingRules.inWindow(taipei(2026, 9, 30, 9), now), isFalse);
    expect(UpcomingRules.inWindow(taipei(2026, 10, 21, 10), now), isTrue);
    expect(UpcomingRules.inWindow(taipei(2026, 10, 21, 11), now), isFalse);
  });

  test('groups by Taipei day and a Monday week', () {
    expect(
      UpcomingRules.group(taipei(2026, 10, 7, 9), now),
      UpcomingGroup.overdue,
    );
    expect(
      UpcomingRules.group(taipei(2026, 10, 7, 23, 59), now),
      UpcomingGroup.today,
    );
    expect(
      UpcomingRules.group(taipei(2026, 10, 11, 23), now),
      UpcomingGroup.thisWeek,
    );
    expect(
      UpcomingRules.group(taipei(2026, 10, 12, 0, 30), now),
      UpcomingGroup.later,
    );
  });

  test('deadline labels match iOS', () {
    expect(UpcomingRules.deadline(taipei(2026, 10, 7, 18), now), '今天 18:00');
    expect(UpcomingRules.deadline(taipei(2026, 10, 8, 9, 5), now), '明天 09:05');
    expect(UpcomingRules.deadline(taipei(2026, 10, 12, 9), now), '5 天後');
    expect(UpcomingRules.deadline(taipei(2026, 10, 7, 8), now), '已逾期・今天 08:00');
    expect(UpcomingRules.deadline(taipei(2026, 10, 4, 8), now), '已逾期 3 天');
  });

  test('only a known, unsubmitted attempt is pending', () {
    Map<String, dynamic> status(String? own, [String? team]) => {
      'lastattempt': {
        if (own != null) 'submission': {'status': own},
        if (team != null) 'teamsubmission': {'status': team},
      },
    };
    expect(UpcomingRules.submitted(status('new')), isFalse);
    expect(UpcomingRules.submitted(status('draft')), isFalse);
    expect(UpcomingRules.submitted(status('submitted')), isTrue);
    expect(UpcomingRules.submitted(status('new', 'submitted')), isTrue);
    expect(UpcomingRules.submitted(status(null)), isNull);
    expect(UpcomingRules.submitted(status('weird')), isNull);
    expect(UpcomingRules.submitted({}), isNull);
  });

  test('demo lists unsubmitted assignments soonest first', () async {
    final items = await loadUpcoming(DemoMoodleRepository(), {
      101: '資料結構',
      104: '機率與統計',
    }, now: DateTime.now());
    expect(items.map((i) => i.id), containsAll([1011, 1041, 1042]));
    expect(items.map((i) => i.id), isNot(contains(1012)));
    expect(items.first.id, 1042);
    expect(items.first.courseName, '機率與統計');
    for (var i = 1; i < items.length; i++) {
      expect(items[i - 1].due.isAfter(items[i].due), isFalse);
    }
  });

  test('page HTML loses scripts and gets the token on school pictures', () {
    final body = moodleHtmlBody(
      '<p onclick="x()">名單</p><script>alert(1)</script>'
      '<img src="https://euni.niu.edu.tw/webservice/pluginfile.php/9/mod_page/content/1/a.png">'
      '<img src="http://elsewhere.example/b.png">'
      '<a href="week2.pdf">講義</a>',
      Uri.parse(
        'https://euni.niu.edu.tw/webservice/pluginfile.php/9/mod_page/content/1/index.html',
      ),
      DemoMoodleRepository(),
    );
    expect(body, isNot(contains('script')));
    expect(body, isNot(contains('onclick')));
    expect(body, contains('a.png?token=demo'));
    expect(body, isNot(contains('elsewhere.example')));
    expect(
      body,
      contains(
        'href="https://euni.niu.edu.tw/webservice/pluginfile.php/9/mod_page/content/1/week2.pdf"',
      ),
    );
  });
}
