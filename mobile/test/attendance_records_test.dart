import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/core/network/school_clients.dart';
import 'package:niu_mobile/features/attendance/attendance_repository.dart';
import 'package:niu_mobile/features/attendance/attendance_screen.dart';
import 'package:niu_mobile/features/moodle/moodle_repository.dart';
import 'package:niu_mobile/shared/shared.dart';

class AttendanceMoodle extends MoodleRepository {
  AttendanceMoodle()
    : super(
        MoodleApiClient(schoolClient('https://euni.niu.edu.tw')),
        const MoodleSession(account: 'student', token: 'rest-token', userId: 7),
      );
  List<Json> modules = [
    {'modname': 'attendance', 'id': 42, 'instance': 9, 'name': '點名冊'},
  ];
  Object? response = {'sessions': [], 'statuses': []};
  bool lookupFails = false;
  int reads = 0;
  @override
  Future<List<Json>> contents(int course) async => [
    {'modules': modules},
  ];
  @override
  Future<Object?> read(
    String function, [
    Map<String, Object> params = const {},
  ]) async {
    reads++;
    if (function == 'core_course_get_course_module') {
      if (lookupFails) throw StateError('unavailable');
      return {
        'cm': {'modname': 'attendance', 'instance': 9},
      };
    }
    expect(function, 'mod_attendance_get_user_sessions');
    expect(params, {'attendanceid': 9, 'userid': 7});
    if (response is Exception) throw response!;
    return response;
  }
}

const recordHtml =
    '<table><tr><th>日期</th><th>描述</th><th>狀態</th></tr><tr><td class="datecol">2026/09/01 08:10</td><td>第一週</td><td>遲到</td></tr></table>';
const emptyHtml = '<table><tr><th>日期</th><th>描述</th><th>狀態</th></tr></table>';
const loginHtml =
    '<form action="/login/index.php"><input name="username"></form>';
final pendingApi = {
  'sessions': [
    {'sessdate': 1788221400, 'description': '第一週', 'statusid': null},
  ],
  'statusses': [],
};

void main() {
  test('attendance date presentation preserves unfamiliar source text', () {
    expect(attendanceDateLines('2026/09/29 11:22-11:32'), [
      '2026/09/29（週二）',
      '11:22–11:32',
    ]);
    expect(attendanceDateLines('校方原始日期'), ['校方原始日期']);
    expect(attendanceDateLines('2026/02/30 11:22'), ['2026/02/30 11:22']);
  });
  for (final dark in [false, true]) {
    testWidgets(
      'attendance hierarchy wraps at 320px and double text dark=$dark',
      (tester) async {
        tester.view.physicalSize = const Size(320, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repository = AttendanceMoodle()
          ..response = {
            'sessions': [
              {
                'sessdate': 1790652120,
                'description': 'QR code 點名',
                'remarks': '自行紀錄的',
                'statusid': 1,
              },
            ],
            'statuses': [
              {'id': 1, 'description': '出席', 'grade': 2},
            ],
          };
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? NiuTheme.dark : NiuTheme.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: Scaffold(
              body: AttendanceRecords(repository: repository, courseId: 1),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(AppCard), findsOneWidget);
        expect(find.text('QR Code 點名'), findsOneWidget);
        expect(find.text('來源：自行記錄'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  test('API failure falls back to same-course read-only HTML URL', () async {
    final moodle = AttendanceMoodle()
      ..response = const FormatException('API unavailable');
    final sections = await AttendanceRepository(
      moodle,
      loadHtml: (uri) async {
        expect(uri.scheme, 'https');
        expect(uri.host, 'euni.niu.edu.tw');
        expect(uri.path, '/mod/attendance/view.php');
        expect(uri.queryParameters, {'id': '42', 'view': '5'});
        return recordHtml;
      },
    ).course(1);
    expect(sections.single.records.single.status, AttendanceStatus.late);
    expect(sections.single.error, isNull);
  });
  test('URL module lookup failure still uses attendance cmid HTML', () async {
    final moodle = AttendanceMoodle()
      ..modules = [
        {
          'modname': 'url',
          'id': 8,
          'instance': 99,
          'url': 'https://euni.niu.edu.tw/mod/attendance/view.php?id=42',
        },
      ]
      ..lookupFails = true;
    final sections = await AttendanceRepository(
      moodle,
      loadHtml: (uri) async {
        expect(uri.queryParameters['id'], '42');
        return recordHtml;
      },
    ).course(1);
    expect(sections.single.records, hasLength(1));
  });
  test(
    'all pending API enriched by HTML and survives login or empty HTML',
    () async {
      for (final source in [recordHtml, loginHtml, emptyHtml]) {
        final sections = await AttendanceRepository(
          AttendanceMoodle()..response = pendingApi,
          loadHtml: (_) async => source,
        ).course(1);
        expect(sections.single.records, hasLength(1));
        expect(
          sections.single.records.single.status,
          source == recordHtml
              ? AttendanceStatus.late
              : AttendanceStatus.pending,
        );
        if (source == loginHtml) expect(sections.single.error, contains('登入'));
      }
    },
  );
  test(
    'login, unrecognized HTML and summary-only page are not empty success',
    () async {
      for (final source in [
        loginHtml,
        '<h1>Server error</h1>',
        '<table class="attlist"><tr><td>日期</td></tr></table>',
      ]) {
        final sections = await AttendanceRepository(
          AttendanceMoodle()..response = const FormatException(),
          loadHtml: (_) async => source,
        ).course(1);
        expect(sections.single.error, isNotNull);
        expect(sections.single.records, isEmpty);
      }
      final sections = await AttendanceRepository(
        AttendanceMoodle()..response = const FormatException(),
        loadHtml: (_) async => emptyHtml,
      ).course(1);
      expect(sections.single.error, isNull);
      expect(sections.single.records, isEmpty);
    },
  );
  test('no modules performs no attendance reads or HTML requests', () async {
    final moodle = AttendanceMoodle()..modules = [];
    expect(
      await AttendanceRepository(
        moodle,
        loadHtml: (_) async => throw StateError('unexpected HTML'),
      ).course(1),
      isEmpty,
    );
    expect(moodle.reads, 0);
  });
  test('known API statuses stay distinct and do not request HTML', () async {
    final moodle = AttendanceMoodle()
      ..response = {
        'sessions': [
          for (var id = 1; id <= 4; id++)
            {'sessdate': 1788221400, 'statusid': id},
        ],
        'statuses': [
          {'id': 1, 'description': '出席', 'grade': 2},
          {'id': 2, 'description': '遲到', 'grade': 1},
          {'id': 3, 'description': '缺席', 'grade': 0},
          {'id': 4, 'description': '', 'acronym': 'E', 'grade': 1},
        ],
      };
    final section = (await AttendanceRepository(
      moodle,
      loadHtml: (_) async => throw StateError('unexpected HTML'),
    ).course(1)).single;
    expect(
      [
        section.present,
        section.late,
        section.absent,
        section.leave,
        section.pending,
      ],
      [1, 1, 1, 1, 0],
    );
    expect(section.records.first.date, matches(r'2026/\d+/\d+ \d\d:\d\d'));
    expect(attendanceStatus('尚未記錄出席'), AttendanceStatus.pending);
  });
  testWidgets(
    'record screen distinguishes no activities and rendered categories',
    (tester) async {
      final moodle = AttendanceMoodle()..modules = [];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AttendanceRecords(repository: moodle, courseId: 1),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('這門課尚未提供點名活動。'), findsOneWidget);
      moodle.modules = [
        {'modname': 'attendance', 'id': 42, 'instance': 9, 'name': '點名冊'},
      ];
      moodle.response = {
        'sessions': [
          {'sessdate': 1788221400, 'statusid': 1},
        ],
        'statuses': [
          {'id': 1, 'description': '請假'},
        ],
      };
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AttendanceRecords(repository: moodle, courseId: 2),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('請假 1'), findsOneWidget);
      expect(find.text('出席 0'), findsOneWidget);
    },
  );
}
