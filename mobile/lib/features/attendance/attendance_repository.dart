import 'package:dio/dio.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:html/parser.dart' as html;
import '../moodle/moodle_repository.dart';
import '../moodle/moodle_web_session.dart';

enum AttendanceStatus { present, late, absent, leave, pending }

AttendanceStatus attendanceStatus(
  String label, {
  num? grade,
  bool recorded = true,
}) {
  if (!recorded) return AttendanceStatus.pending;
  final s = label.trim().toLowerCase();
  if (s.isEmpty ||
      [
        '尚未',
        '未簽到',
        '未記錄',
        '未紀錄',
        '未結算',
        'not set',
        'unknown',
        'pending',
      ].any(s.contains)) {
    return AttendanceStatus.pending;
  }
  if (s == 'l' || ['遲到', 'late'].any(s.contains)) {
    return AttendanceStatus.late;
  }
  if (s == 'e' || ['請假', 'leave', 'excused'].any(s.contains)) {
    return AttendanceStatus.leave;
  }
  if (s == 'a' || ['未到', '缺席', '曠課', 'absent'].any(s.contains)) {
    return AttendanceStatus.absent;
  }
  if (s == 'p' || ['出席', 'present'].any(s.contains)) {
    return AttendanceStatus.present;
  }
  return grade == null
      ? AttendanceStatus.pending
      : grade > 0
      ? AttendanceStatus.present
      : AttendanceStatus.absent;
}

class AttendanceRecord {
  const AttendanceRecord(
    this.date,
    this.description,
    this.label,
    this.remarks,
    this.status,
  );
  final String date, description, label, remarks;
  final AttendanceStatus status;
}

class AttendanceSection {
  const AttendanceSection(this.name, this.moduleId, this.records, {this.error});
  final String name;
  final int moduleId;
  final List<AttendanceRecord> records;
  final String? error;
  int get present =>
      records.where((r) => r.status == AttendanceStatus.present).length;
  int get absent =>
      records.where((r) => r.status == AttendanceStatus.absent).length;
  int get late =>
      records.where((r) => r.status == AttendanceStatus.late).length;
  int get leave =>
      records.where((r) => r.status == AttendanceStatus.leave).length;
  int get pending =>
      records.where((r) => r.status == AttendanceStatus.pending).length;
  String get rate => present + absent == 0
      ? '—'
      : '${(present * 100 / (present + absent)).toStringAsFixed(0)}%';
}

class AttendanceRepository {
  AttendanceRepository(this.moodle, {this.loadHtml, this.signInAndLoad});
  final MoodleRepository moodle;

  /// Optional school-session HTML loader; foreground WebView remains available.
  final Future<String> Function(Uri uri)? loadHtml;

  /// Signs the WebView into the M 園區 website and returns the page. Used
  /// only when the cookie-based read lands on the login page (first visit).
  final Future<String> Function(Uri uri)? signInAndLoad;

  static bool isLoginPage(String source) =>
      html
          .parse(source)
          .querySelector(
            'input[name="username"], input[name="password"], #page-login-index, form[action*="/login/"]',
          ) !=
      null;

  /// Cookie read first; on a login redirect or page, sign in once and retry
  /// through the website itself. The resulting cookies serve later reads.
  Future<String> _page(Uri uri) async {
    final read = loadHtml ?? _readHtml;
    String? source;
    try {
      source = await read(uri);
    } on FormatException {
      source = null;
    }
    if (source != null && !isLoginPage(source)) return source;
    moodle.requireCurrent();
    return (signInAndLoad ?? (u) => MoodleWebSession.load(moodle, u))(uri);
  }

  /// REST tokens do not authenticate ordinary Moodle pages. Reuse only the
  /// school's WebView cookies, never append a token or execute a marking URL.
  Future<String> _readHtml(Uri uri) async {
    moodle.requireCurrent();
    final cookies = await CookieManager.instance()
        .getCookies(url: WebUri('$uri'))
        .timeout(const Duration(seconds: 5));
    moodle.requireCurrent();
    final response = await moodle.api.http
        .get<String>(
          '$uri',
          options: Options(
            responseType: ResponseType.plain,
            followRedirects: false,
            validateStatus: (status) => status != null && status < 400,
            headers: {
              'Accept': 'text/html',
              'Cookie': cookies.map((c) => '${c.name}=${c.value}').join('; '),
            },
          ),
        )
        .timeout(const Duration(seconds: 20));
    moodle.requireCurrent();
    if (response.statusCode != 200) {
      throw const FormatException('M 園區網站尚未登入');
    }
    return response.data ?? '';
  }

  Future<List<AttendanceSection>> course(int course) async {
    final result = <AttendanceSection>[];
    for (final section in await moodle.contents(course)) {
      for (final module in objects(section['modules'])) {
        final uri = Uri.tryParse('${module['url']}');
        if (module['modname'] != 'attendance' &&
            !(uri?.host == 'euni.niu.edu.tw' &&
                uri?.path == '/mod/attendance/view.php')) {
          continue;
        }
        final cmid = module['modname'] == 'attendance'
            ? int.tryParse('${module['id']}')
            : int.tryParse(uri?.queryParameters['id'] ?? '');
        if (cmid == null || cmid <= 0) continue;
        try {
          List<AttendanceRecord>? records;
          String? fallbackError;
          try {
            var instance = module['modname'] == 'attendance'
                ? module['instance']
                : null;
            if (instance == null) {
              final cm = object(
                object(
                  await moodle.read('core_course_get_course_module', {
                    'cmid': cmid,
                  }),
                )['cm'],
              );
              if (cm['modname'] != 'attendance') {
                throw const FormatException('非點名模組');
              }
              instance = cm['instance'];
            }
            records = parseApi(
              object(
                await moodle.read('mod_attendance_get_user_sessions', {
                  'attendanceid': number(instance),
                  'userid': moodle.session.userId,
                }),
              ),
            );
          } catch (_) {
            // Instance lookup and unavailable/malformed APIs both use HTML.
          }
          if (records == null ||
              records.every((r) => r.status == AttendanceStatus.pending)) {
            try {
              final parsed = parseHtml(
                await _page(
                  Uri.https('euni.niu.edu.tw', '/mod/attendance/view.php', {
                    'id': '$cmid',
                    'view': '5',
                  }),
                ),
              );
              if (parsed.isNotEmpty || records == null) records = parsed;
            } catch (error) {
              if (records == null) rethrow;
              fallbackError = error is FormatException
                  ? error.message
                  : '校方網頁暫時無法讀取，以下保留 API 紀錄。';
            }
          }
          moodle.requireCurrent();
          result.add(
            AttendanceSection(
              plain(module['name']),
              cmid,
              records,
              error: fallbackError,
            ),
          );
        } catch (error) {
          moodle.requireCurrent();
          result.add(
            AttendanceSection(
              plain(module['name']),
              cmid,
              const [],
              error: error is FormatException
                  ? error.message
                  : '無法讀取點名紀錄，請重試或開啟校方紀錄。',
            ),
          );
        }
      }
    }
    return result;
  }

  static List<AttendanceRecord> parseApi(Json data) {
    final statuses = {
      for (final s in objects(data['statuses'] ?? data['statusses'] ?? []))
        number(s['id']): s,
    };
    final sessions = objects(data['sessions']);
    sessions.sort(
      (a, b) => number(b['sessdate']).compareTo(number(a['sessdate'])),
    );
    return sessions.map((s) {
      final status = statuses[int.tryParse('${s['statusid']}')];
      final description = plain(status?['description']).trim();
      final label = description.isNotEmpty
          ? description
          : plain(status?['acronym'] ?? '尚未點名');
      return AttendanceRecord(
        campusTime(s['sessdate']),
        plain(s['description']),
        label,
        plain(s['remarks']),
        attendanceStatus(
          label,
          grade: num.tryParse('${status?['grade']}'),
          recorded: status != null,
        ),
      );
    }).toList();
  }

  static List<AttendanceRecord> parseHtml(String source) {
    final doc = html.parse(source);
    if (isLoginPage(source)) {
      throw const FormatException('無法自動登入 M 園區網站，請開啟校方紀錄登入一次。');
    }
    final result = <AttendanceRecord>[];
    for (final row
        in doc
            .querySelectorAll('table')
            .where((t) => !t.classes.contains('attlist'))
            .expand((t) => t.querySelectorAll('tr'))) {
      final cells = row.querySelectorAll('td');
      if (cells.length < 3) continue;
      String cell(String cls, int index) =>
          (row.querySelector('.$cls')?.text ??
                  (cells.length > index ? cells[index].text : ''))
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim();
      final date = cell('datecol', 0);
      if (!RegExp(r'\d{4}[年/\-]\s*\d{1,2}[月/\-]\s*\d{1,2}').hasMatch(date)) {
        continue;
      }
      final label = cell('statuscol', 2);
      result.add(
        AttendanceRecord(
          date,
          cell('desccol', 1),
          label,
          cell('remarkscol', 4),
          attendanceStatus(label),
        ),
      );
    }
    if (result.isEmpty &&
        !doc
            .querySelectorAll('table')
            .any(
              (t) =>
                  !t.classes.contains('attlist') &&
                  ((t.text.contains('日期') && t.text.contains('狀態')) ||
                      (t.text.toLowerCase().contains('date') &&
                          t.text.toLowerCase().contains('status')) ||
                      t.querySelector('.datecol') != null),
            )) {
      throw const FormatException('無法辨識校方點名紀錄');
    }
    return result;
  }
}

Uri? attendanceQr(String raw) {
  final u = Uri.tryParse(raw.trim());
  if (u == null ||
      u.scheme != 'https' ||
      u.host != 'euni.niu.edu.tw' ||
      u.port != 443 ||
      u.userInfo.isNotEmpty ||
      u.path.toLowerCase() != '/mod/attendance/attendance.php') {
    return null;
  }
  final q = <String, List<String>>{};
  for (final e in u.queryParametersAll.entries) {
    q.putIfAbsent(e.key.toLowerCase(), () => []).addAll(e.value);
  }
  if (q.length != 2 || q['qrpass']?.length != 1 || q['sessid']?.length != 1) {
    return null;
  }
  final pass = q['qrpass']!.single;
  final session = q['sessid']!.single;
  if (pass.isEmpty || pass.length > 256 || (int.tryParse(session) ?? 0) <= 0) {
    return null;
  }
  return Uri.https('euni.niu.edu.tw', '/mod/attendance/attendance.php', {
    'qrpass': pass,
    'sessid': session,
  });
}

enum AttendanceOutcome {
  recorded,
  alreadyRecorded,
  expired,
  requiresAction,
  failed,
  unknown,
}

AttendanceOutcome attendanceOutcome({
  required Uri original,
  required Uri response,
  required String body,
  required String notifications,
  required bool hasForm,
  List<String> errorCodes = const [],
}) {
  if (response.scheme != 'https' ||
      response.host != 'euni.niu.edu.tw' ||
      response.port != 443 ||
      response.userInfo.isNotEmpty) {
    return AttendanceOutcome.unknown;
  }
  final text = '$notifications\n$body'.toLowerCase();
  final compact = text.replaceAll(RegExp(r'\s+'), '');
  if (errorCodes.any((e) => ['qr_pass_wrong', 'qr_cookie_error'].contains(e)) ||
      [
        'qr code has expired',
        'qr session has expired',
        'qr code expired',
        'qr碼已過期',
        'qr code 已過期',
        'qrcode已過期',
        'qr代碼已過期',
        '二維碼已過期',
        '二维码已过期',
      ].any((p) => compact.contains(p.replaceAll(' ', '')))) {
    return AttendanceOutcome.expired;
  }
  if (attendanceQr('$response') == attendanceQr('$original') &&
      attendanceQr('$original') != null &&
      [
        'attendance has already been set',
        '您的出缺席已經設置好了',
        'your attendance has already been marked as',
        '出席已被標記為',
        '出席已標記為',
      ].any(text.contains)) {
    return AttendanceOutcome.alreadyRecorded;
  }
  if (hasForm) return AttendanceOutcome.requiresAction;
  if ([
    'incorrect password',
    'attendance has not been recorded',
    'no valid status was available',
    'not currently available for self-marking',
    'not a member of the course group',
    'outside the allowed subnet',
    'not in the allowed range',
    'device appears to have been used to record attendance for another student',
    '沒有可用的有效狀態',
    '學生只可以從某些特定的位置上紀錄出缺席',
    '自我標記已被禁用',
    '密碼不正確',
    '密碼錯誤',
    '尚未開放',
    '未開放點名',
    '沒有可用的出席狀態',
    '不在允許的網路範圍',
    '不在允許的子網路',
    '其他學生使用此裝置',
    '未記錄出席',
    '未紀錄出席',
  ].any(text.contains)) {
    return AttendanceOutcome.failed;
  }
  if (response.path == '/mod/attendance/view.php' &&
      (int.tryParse(response.queryParameters['id'] ?? '') ?? 0) > 0 &&
      [
        'your attendance in this session has been recorded',
        'attendance in this session has been recorded',
        '您在此上課時段的出席已被記錄',
        '您在此上課時段的出席已被紀錄',
      ].any(notifications.toLowerCase().contains)) {
    return AttendanceOutcome.recorded;
  }
  return AttendanceOutcome.unknown;
}
