import 'dart:convert';
import 'package:html/parser.dart' as html;
import 'dart:typed_data';
import 'package:dio/dio.dart';
import '../../core/network/school_clients.dart';
import '../../core/session/campus_session.dart';

typedef Json = Map<String, dynamic>;
Json object(Object? value) {
  if (value is Map<String, dynamic>) return value;
  throw const FormatException('學校回傳的資料格式不正確');
}

List<Json> objects(Object? value) {
  if (value is! List) throw const FormatException('學校回傳的清單格式不正確');
  return value.map(object).toList();
}

int number(Object? value) {
  final parsed = value is int ? value : int.tryParse('$value');
  if (parsed == null) throw const FormatException('學校回傳的編號格式不正確');
  return parsed;
}

String plain(Object? value) => html.parseFragment('${value ?? ''}').text ?? '';
String campusTime(Object? value) {
  final ts = int.tryParse('$value') ?? 0;
  if (ts <= 0) return '未設定';
  final d = DateTime.fromMillisecondsSinceEpoch(
    ts * 1000,
    isUtc: true,
  ).add(const Duration(hours: 8));
  return '${d.year}/${d.month}/${d.day} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

class MoodleSession {
  const MoodleSession({
    required this.account,
    required this.token,
    required this.userId,
    this.privateToken,
  });
  final String account, token;
  final int userId;
  final String? privateToken;
}

class MoodleRepository {
  MoodleRepository(this.api, this.session);
  final MoodleApiClient api;
  final MoodleSession session;
  bool _invalidated = false;
  CampusSession? _owner;
  int? _epoch;
  void bindSession(CampusSession owner) {
    if (identical(_owner, owner)) return;
    _owner?.unregisterCleanup(invalidate);
    _owner = owner;
    _epoch = owner.coordinator.epoch;
    owner.registerCleanup(invalidate);
  }

  Future<void> invalidate() async {
    _invalidated = true;
    _owner?.unregisterCleanup(invalidate);
  }

  void requireCurrent() => _guard();
  Future<Uint8List> download(String raw) async {
    final uri = fileUri(raw);
    final response = await api.http.get<List<int>>(
      '$uri',
      options: Options(
        responseType: ResponseType.bytes,
        followRedirects: false,
      ),
    );
    _guard();
    final bytes = response.data;
    final type = response.headers.value('content-type') ?? '';
    if (response.statusCode != 200 ||
        bytes == null ||
        bytes.isEmpty ||
        (type.contains('text/html') && !_htmlFile(uri, bytes)) ||
        (type.contains('application/json') && _errorJson(bytes))) {
      throw const FormatException('校方未提供有效附件，請重新登入');
    }
    return Uint8List.fromList(bytes);
  }

  /// An .html material is served as text/html too; only a login page is not
  /// the file the student asked for.
  static bool _htmlFile(Uri uri, List<int> bytes) {
    if (!RegExp(r'\.x?html?$').hasMatch(uri.path.toLowerCase())) return false;
    final page = html.parse(utf8.decode(bytes, allowMalformed: true));
    return page.querySelector(
          'input[name="password"], #page-login-index, form[action*="/login/"]',
        ) ==
        null;
  }

  /// Web service failures come back as a JSON object naming the error; any
  /// other JSON is a .json material.
  static bool _errorJson(List<int> bytes) {
    try {
      final value = jsonDecode(utf8.decode(bytes));
      return value is Map &&
          (value.containsKey('errorcode') || value.containsKey('exception'));
    } catch (_) {
      return false;
    }
  }

  void _guard() {
    if (_invalidated) throw StateError('M 園區登入已失效');
    final owner = _owner;
    if (owner != null) {
      owner.coordinator.requireCurrent(_epoch!);
      if (!owner.hasLocalAccount ||
          owner.account?.toLowerCase() != session.account.toLowerCase()) {
        throw StateError('M 園區帳號與校務登入不符');
      }
    }
  }

  static Future<MoodleRepository> login(
    MoodleApiClient api,
    String account,
    String password,
  ) async {
    final auth = await api.authenticateSession(account, password);
    final token = auth['token'] as String;
    final site = object(
      await api.read(token, 'core_webservice_get_site_info', {}),
    );
    if (site['username'] is! String ||
        '${site['username']}'.toLowerCase() != account.trim().toLowerCase()) {
      throw StateError('M 園區登入身分不符');
    }
    return MoodleRepository(
      api,
      MoodleSession(
        account: account,
        token: token,
        userId: number(site['userid']),
        privateToken: auth['privatetoken'] as String?,
      ),
    );
  }

  Future<Object?> read(
    String function, [
    Map<String, Object> params = const {},
  ]) async {
    _guard();
    final value = await api.read(session.token, function, params);
    _guard();
    return value;
  }

  Future<Object?> _mutate(String function, Map<String, Object> params) async {
    _guard();
    final value = await api.mutate(session.token, function, params);
    _guard();
    return value;
  }

  Future<List<Json>> courses() async => objects(
    await read('core_enrol_get_users_courses', {'userid': session.userId}),
  );
  Future<List<Json>> contents(int course) async =>
      objects(await read('core_course_get_contents', {'courseid': course}));
  Future<List<Json>> forums(int course) async => objects(
    await read('mod_forum_get_forums_by_courses', {'courseids[0]': course}),
  );
  Future<List<Json>> discussions(int forum, {int page = 0}) async => objects(
    object(
      await read('mod_forum_get_forum_discussions', {
        'forumid': forum,
        'sortorder': 3,
        'perpage': 20,
        'page': page,
      }),
    )['discussions'],
  );
  Future<List<Json>> posts(int discussion) async => objects(
    object(
      await read('mod_forum_get_discussion_posts', {
        'discussionid': discussion,
      }),
    )['posts'],
  );
  Future<List<Json>> announcements(int course) async {
    final result = <Json>[];
    for (final forum in await forums(course)) {
      if (forum['type'] == 'news' || '${forum['name']}'.contains('公告')) {
        result.addAll(await discussions(number(forum['id'])));
      }
    }
    result.sort(
      (a, b) => number(b['timemodified']).compareTo(number(a['timemodified'])),
    );
    return result;
  }

  Future<List<Json>> assignments(int course) async {
    final groups = objects(
      object(
        await read('mod_assign_get_assignments', {'courseids[0]': course}),
      )['courses'],
    );
    return groups.expand((g) => objects(g['assignments'])).toList();
  }

  Future<Json> submission(int assignment) async => object(
    await read('mod_assign_get_submission_status', {'assignid': assignment}),
  );
  Future<List<Json>> grades(int course) async {
    final users = objects(
      object(
        await read('gradereport_user_get_grade_items', {
          'courseid': course,
          'userid': session.userId,
        }),
      )['usergrades'],
    );
    return users.expand((u) => objects(u['gradeitems'])).toList();
  }

  Future<List<Json>> notifications() async => objects(
    object(
      await read('core_message_get_messages', {
        'useridto': session.userId,
        'useridfrom': 0,
        'type': 'notifications',
        'newestfirst': 1,
        'limitfrom': 0,
        'limitnum': 100,
      }),
    )['messages'],
  );
  Future<int> draft() async {
    final value = await _mutate('core_files_get_unused_draft_itemid', {});
    final id = number(value is Map ? value['itemid'] : value);
    if (id <= 0) throw const FormatException('無效的草稿編號');
    return id;
  }

  Future<void> save(int assignment, int draftId) async {
    _checkMutation(
      await _mutate('mod_assign_save_submission', {
        'assignmentid': assignment,
        'plugindata[files_filemanager]': draftId,
      }),
    );
  }

  Future<void> uploadFiles(
    int assignment,
    List<({String name, List<int> bytes})> files,
  ) async {
    var id = await draft();
    for (final file in files) {
      _guard();
      final response = await api.upload(
        session.token,
        id,
        file.name,
        file.bytes,
      );
      final uploaded = response is List && response.isNotEmpty
          ? object(response.first)
          : object(response);
      _guard();
      id = number(uploaded['itemid']);
      if (id <= 0) throw const FormatException('校方未確認收到檔案');
    }
    await save(assignment, id);
  }

  Future<void> clear(int assignment) async => save(assignment, await draft());
  Future<void> submit(int assignment, {required bool acceptStatement}) async {
    _checkMutation(
      await _mutate('mod_assign_submit_for_grading', {
        'assignmentid': assignment,
        'acceptsubmissionstatement': acceptStatement ? 1 : 0,
      }),
    );
  }

  void _checkMutation(Object? response) {
    if (response == null) return;
    if (response is List && response.isEmpty) return;
    if (response is Map &&
        response['warnings'] is List &&
        (response['warnings'] as List).isEmpty) {
      return;
    }
    throw const SchoolApiException('moodle_mutation_not_confirmed');
  }

  Uri fileUri(String raw) {
    _guard();
    final uri = Uri.parse(raw);
    if (uri.scheme != 'https' ||
        uri.host != 'euni.niu.edu.tw' ||
        uri.userInfo.isNotEmpty ||
        uri.port != 443) {
      throw const FormatException('無法開啟非 M 園區檔案');
    }
    return uri.replace(
      path: uri.path.replaceFirst(
        RegExp(r'^/pluginfile.php'),
        '/webservice/pluginfile.php',
      ),
      queryParameters: {...uri.queryParameters, 'token': session.token},
    );
  }

  Future<Uri> webUri(Uri target) async {
    _guard();
    if (target.scheme != 'https' ||
        target.host != 'euni.niu.edu.tw' ||
        target.port != 443 ||
        target.userInfo.isNotEmpty) {
      throw const FormatException('無法開啟非 M 園區網址');
    }
    if (session.privateToken == null) return target;
    final result = object(
      await _mutate('tool_mobile_get_autologin_key', {
        'privatetoken': session.privateToken!,
      }),
    );
    final key = result['key'];
    if (key is! String || key.isEmpty) {
      throw const FormatException('無法取得網頁登入金鑰');
    }
    return Uri.https('euni.niu.edu.tw', '/admin/tool/mobile/autologin.php', {
      'userid': '${session.userId}',
      'key': key,
      'urltogo': '$target',
    });
  }
}
