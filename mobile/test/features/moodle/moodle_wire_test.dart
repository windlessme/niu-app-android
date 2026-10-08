import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/core/network/school_clients.dart';
import 'package:niu_mobile/features/moodle/moodle_repository.dart';
import 'package:niu_mobile/features/attendance/attendance_repository.dart';
import 'package:niu_mobile/features/library/library_repository.dart';
import '../../support/fakes.dart';

void main() {
  MoodleRepository repo(WireAdapter adapter) {
    final dio = schoolClient('https://euni.niu.edu.tw')
      ..httpClientAdapter = adapter;
    return MoodleRepository(
      MoodleApiClient(dio),
      const MoodleSession(account: 'b123', token: 'secret', userId: 7),
    );
  }

  Map<String, String> form(RequestOptions r) =>
      Uri.splitQueryString(r.extra['wireBody'] as String);
  test('login form preserves plus and credentials stay out of URL', () async {
    final adapter = WireAdapter(
      (r) => r.path == '/login/token.php'
          ? {'token': 't', 'privatetoken': 'p'}
          : {'userid': 17, 'username': 'a+b'},
    );
    final api = MoodleApiClient(
      schoolClient('https://euni.niu.edu.tw')..httpClientAdapter = adapter,
    );
    final session = await MoodleRepository.login(api, 'a+b', 'p+&=密碼');
    expect(form(adapter.requests.first)['password'], 'p+&=密碼');
    expect(adapter.requests.first.uri.query, isEmpty);
    expect(session.session.userId, 17);
    expect(session.session.privateToken, 'p');
  });
  test('read uses exact Moodle array keys and user ID', () async {
    final adapter = WireAdapter((r) => {'usergrades': []});
    await repo(adapter).grades(31);
    expect(form(adapter.requests.single), containsPair('userid', '7'));
    expect(form(adapter.requests.single), containsPair('courseid', '31'));
    expect(
      form(adapter.requests.single)['wsfunction'],
      'gradereport_user_get_grade_items',
    );
    expect(adapter.requests.single.method, 'POST');
  });
  test('web autologin keeps private token in encoded POST body', () async {
    final adapter = WireAdapter((_) => {'key': 'one-time-key'});
    final repository = MoodleRepository(
      MoodleApiClient(
        schoolClient('https://euni.niu.edu.tw')..httpClientAdapter = adapter,
      ),
      const MoodleSession(
        account: 'b123',
        token: 't',
        userId: 7,
        privateToken: 'p+&=',
      ),
    );
    final target = Uri.parse(
      'https://euni.niu.edu.tw/mod/attendance/view.php?id=4',
    );
    final entry = await repository.webUri(target);
    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(form(request)['privatetoken'], 'p+&=');
    expect(request.uri.queryParameters.containsKey('privatetoken'), false);
    expect(entry.queryParameters['urltogo'], '$target');
    expect(entry.queryParameters['key'], 'one-time-key');
    expect(entry.toString(), isNot(contains('privatetoken')));
  });
  test('save sends bracketed plugin key exactly once on rejection', () async {
    final adapter = WireAdapter(
      (r) => {'exception': 'moodle_exception', 'message': 'rejected'},
    );
    await expectLater(
      repo(adapter).save(12, 99),
      throwsA(isA<SchoolApiException>()),
    );
    expect(adapter.requests, hasLength(1));
    expect(
      form(adapter.requests.single)['plugindata[files_filemanager]'],
      '99',
    );
    expect(form(adapter.requests.single)['assignmentid'], '12');
  });
  test('uncertain submission network outcome is not retried', () async {
    final adapter = WireAdapter(
      (r) => DioException(
        requestOptions: r,
        type: DioExceptionType.receiveTimeout,
      ),
    );
    await expectLater(
      repo(adapter).submit(12, acceptStatement: true),
      throwsA(isA<DioException>()),
    );
    expect(adapter.requests, hasLength(1));
    expect(form(adapter.requests.single)['acceptsubmissionstatement'], '1');
  });
  test('draft string/map variants parsed with one allocation', () async {
    for (final value in [
      '56',
      {'itemid': '56'},
    ]) {
      final adapter = WireAdapter((_) => value);
      expect(await repo(adapter).draft(), 56);
      expect(adapter.requests, hasLength(1));
    }
  });
  test('upload uses Moodle multipart and saves only confirmed draft', () async {
    final adapter = WireAdapter((r) {
      if (r.path == '/webservice/upload.php') {
        return [
          {'itemid': 61, 'filename': 'work.txt'},
        ];
      }
      final f = form(r)['wsfunction'];
      return f == 'core_files_get_unused_draft_itemid' ? 60 : [];
    });
    await repo(adapter).uploadFiles(12, [
      (name: 'work.txt', bytes: [65, 66]),
    ]);
    expect(adapter.requests, hasLength(3));
    final upload = adapter.requests[1];
    expect(
      upload.extra['wireBody'],
      contains('name="file_1"; filename="work.txt"'),
    );
    expect(upload.extra['wireBody'], contains('name="itemid"\r\n\r\n60'));
    expect(upload.uri.query, isEmpty);
    expect(form(adapter.requests.last)['plugindata[files_filemanager]'], '61');
  });
  test('ambiguous upload never triggers second upload or save', () async {
    final adapter = WireAdapter(
      (r) => r.path == '/webservice/upload.php' ? [] : 60,
    );
    await expectLater(
      repo(adapter).uploadFiles(12, [
        (name: 'work.txt', bytes: [65]),
      ]),
      throwsFormatException,
    );
    expect(adapter.requests, hasLength(2));
  });
  test('malformed courses are not reported as empty success', () async {
    await expectLater(
      repo(WireAdapter((_) => {'unexpected': []})).courses(),
      throwsFormatException,
    );
  });
  test('logout invalidation blocks subsequent reads and mutations', () async {
    final adapter = WireAdapter((_) => []);
    final repository = repo(adapter);
    await repository.invalidate();
    await expectLater(repository.courses(), throwsStateError);
    await expectLater(
      repository.submit(12, acceptStatement: true),
      throwsStateError,
    );
    expect(adapter.requests, isEmpty);
  });
  test('warnings reject mutation success', () async {
    await expectLater(
      repo(
        WireAdapter(
          (_) => [
            {'warningcode': 'bad'},
          ],
        ),
      ).save(1, 2),
      throwsA(isA<SchoolApiException>()),
    );
  });
  test('file token is constrained to the exact HTTPS Moodle origin', () {
    final repository = repo(WireAdapter((_) => []));
    expect(
      repository.fileUri('https://euni.niu.edu.tw/pluginfile.php/3/a.pdf').path,
      '/webservice/pluginfile.php/3/a.pdf',
    );
    expect(
      () => repository.fileUri(
        'https://euni.niu.edu.tw.evil.test/pluginfile.php',
      ),
      throwsFormatException,
    );
    expect(
      () => repository.fileUri('http://euni.niu.edu.tw/pluginfile.php'),
      throwsFormatException,
    );
  });
  test('attendance legacy statusses and missing status remain pending', () {
    final records = AttendanceRepository.parseApi({
      'sessions': [
        {'id': 1, 'sessdate': 100, 'statusid': 2},
        {'id': 2, 'sessdate': 200},
      ],
      'statusses': [
        {'id': 2, 'description': '缺席', 'grade': 0},
      ],
    });
    expect(records.first.status, AttendanceStatus.pending);
    expect(records.last.status, AttendanceStatus.absent);
    expect(attendanceStatus('請假'), AttendanceStatus.leave);
    expect(
      () => AttendanceRepository.parseApi({'sessions': 'bad'}),
      throwsFormatException,
    );
  });
  test('attendance HTML login and unrelated tables are parsing errors', () {
    expect(
      () => AttendanceRepository.parseHtml(
        '<form><input name="password"></form>',
      ),
      throwsFormatException,
    );
    expect(
      () => AttendanceRepository.parseHtml(
        '<table><tr><td>hello</td></tr></table>',
      ),
      throwsFormatException,
    );
    final records = AttendanceRepository.parseHtml(
      '<table><tr><th>日期</th></tr><tr><td class="datecol">2026年9月1日</td><td>課程</td><td>尚未點名</td></tr></table>',
    );
    expect(records.single.status, AttendanceStatus.pending);
  });
  test('a shared link is found inside a classmate\'s message', () {
    const link =
        'https://euni.niu.edu.tw/mod/attendance/attendance.php?qrpass=RAjWP5gHWP6P6Jg&sessid=3032';
    for (final text in [
      link,
      '  $link\n',
      '點名連結：$link 快點',
      '「$link」',
      'euni.niu.edu.tw/mod/attendance/attendance.php?qrpass=RAjWP5gHWP6P6Jg&sessid=3032',
    ]) {
      expect('${attendanceLink(text)}', link, reason: text);
    }
    for (final text in [
      '',
      'http://euni.niu.edu.tw/mod/attendance/attendance.php?qrpass=a&sessid=1',
      'https://example.org/mod/attendance/attendance.php?qrpass=a&sessid=1',
      'https://euni.niu.edu.tw/mod/attendance/attendance.php?qrpass=a&sessid=0',
      'https://euni.niu.edu.tw/mod/attendance/attendance.php?qrpass=a&sessid=1&next=https://x',
      'https://euni.niu.edu.tw/my/',
    ]) {
      expect(attendanceLink(text), isNull, reason: text);
    }
  });
  test('QR rejects extra keys, duplicate keys and foreign origins', () {
    const url =
        'https://euni.niu.edu.tw/mod/attendance/attendance.php?qrpass=a%2Bb&sessid=5';
    expect(attendanceQr(url)!.queryParameters['qrpass'], 'a+b');
    expect(attendanceQr('$url&sessid=5'), isNull);
    expect(attendanceQr('$url&redirect=x'), isNull);
    expect(
      attendanceQr(url.replaceFirst('euni.niu.edu.tw', 'evil.test')),
      isNull,
    );
    expect(attendanceQr(url.replaceFirst('https:', 'http:')), isNull);
  });
  test('attendance success requires explicit notification on module view', () {
    final original = attendanceQr(
      'https://euni.niu.edu.tw/mod/attendance/attendance.php?qrpass=abc&sessid=5',
    )!;
    final view = Uri.parse(
      'https://euni.niu.edu.tw/mod/attendance/view.php?id=17',
    );
    AttendanceOutcome classify({
      Uri? response,
      String body = '',
      String notice = '',
      bool form = false,
      List<String> codes = const [],
    }) => attendanceOutcome(
      original: original,
      response: response ?? view,
      body: body,
      notifications: notice,
      hasForm: form,
      errorCodes: codes,
    );
    const recorded = 'Your attendance in this session has been recorded';
    expect(classify(body: recorded), AttendanceOutcome.unknown);
    expect(classify(notice: recorded), AttendanceOutcome.recorded);
    expect(
      classify(notice: recorded, form: true),
      AttendanceOutcome.requiresAction,
    );
    expect(
      classify(notice: recorded, codes: ['qr_cookie_error']),
      AttendanceOutcome.expired,
    );
    expect(classify(notice: recorded, body: '密碼錯誤'), AttendanceOutcome.failed);
    expect(
      classify(response: original, body: 'attendance has already been set'),
      AttendanceOutcome.alreadyRecorded,
    );
    expect(
      classify(body: 'attendance has already been set'),
      AttendanceOutcome.unknown,
    );
    expect(
      classify(
        response: Uri.parse('https://evil.test/mod/attendance/view.php?id=1'),
        notice: recorded,
      ),
      AttendanceOutcome.unknown,
    );
  });
  test('library number endpoint JSON account is normalized', () async {
    final adapter = WireAdapter((_) => {'no': ''});
    final repository = LibraryRepository(
      schoolClient('https://sso.niu.edu.tw')..httpClientAdapter = adapter,
    );
    await expectLater(
      repository.image(' B123 ', LibraryCodeKind.entrance),
      throwsFormatException,
    );
    final request = adapter.requests.single;
    expect(request.path, '/QRCode/Number/');
    expect(jsonDecode(request.extra['wireBody'] as String), {
      'role': 'student',
      'acnt': 'b123',
    });
    expect(request.uri.query, isEmpty);
  });
}
