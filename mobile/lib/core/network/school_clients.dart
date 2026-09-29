import 'package:dio/dio.dart';

class SchoolApiException implements Exception {
  const SchoolApiException(this.code);
  final String code;
  @override
  String toString() => 'SchoolApiException($code)';
}

/// No global credential interceptor and no automatic mutation retries.
Dio schoolClient(String origin) {
  if (!const {
    'https://euni.niu.edu.tw',
    'https://ccsys1.niu.edu.tw',
    'https://sso.niu.edu.tw',
  }.contains(origin)) {
    throw ArgumentError.value(origin, 'origin', 'Unknown school API origin');
  }
  return Dio(
    BaseOptions(
      baseUrl: origin,
      connectTimeout: const Duration(seconds: 20),
      sendTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 30),
      followRedirects: false,
    ),
  );
}

class SsoApiClient {
  SsoApiClient(this.http) {
    if (http.options.baseUrl != 'https://ccsys1.niu.edu.tw') {
      throw ArgumentError('SSO requires its own school origin');
    }
  }
  final Dio http;

  /// Discover identity only through the school's authenticated endpoint.
  Future<Map<String, dynamic>> info(String token) async {
    final response = await http.get<Map<String, dynamic>>(
      '/SSO/API/Authorization/info',
      options: Options(
        headers: {
          'Authorization': 'Bearer $token',
          'Referer': 'https://ccsys1.niu.edu.tw/SSO/login',
        },
      ),
    );
    final data = response.data?['data'];
    if (data is! Map<String, dynamic> ||
        data['acnt'] is! String ||
        (data['acnt'] as String).trim().isEmpty) {
      throw const SchoolApiException('sso_identity_missing');
    }
    return {...data, 'acnt': (data['acnt'] as String).trim().toLowerCase()};
  }

  Future<Map<String, dynamic>> verifyIdentity(
    String token,
    String account,
  ) async {
    final data = await info(token);
    if (data['acnt'] != account.trim().toLowerCase()) {
      throw const SchoolApiException('sso_identity_mismatch');
    }
    return data;
  }

  Future<Uri> academicEntry(String token, String account) async {
    final response = await http.get<Map<String, dynamic>>(
      '/SSO/API/GUID/${Uri.encodeComponent(account.toLowerCase())}',
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
    final guid = response.data?['guid'];
    if (guid is! String || guid.isEmpty) {
      throw const SchoolApiException('sso_guid_missing');
    }
    return Uri.https('acade.niu.edu.tw', '/NIU/Login.aspx', {'GUID': guid});
  }
}

class MoodleApiClient {
  MoodleApiClient(this.http) {
    if (http.options.baseUrl != 'https://euni.niu.edu.tw') {
      throw ArgumentError('Moodle requires its own school origin');
    }
    http.options.headers.addAll({
      'User-Agent': 'MoodleMobile/4.5.0 (Android)',
      'Accept': 'application/json, text/plain, */*',
      'X-Requested-With': 'XMLHttpRequest',
    });
  }
  final Dio http;

  Future<String> authenticate(String username, String password) async {
    return (await authenticateSession(username, password))['token'] as String;
  }

  Future<Map<String, dynamic>> authenticateSession(
    String username,
    String password,
  ) async {
    final response = await http.post<Map<String, dynamic>>(
      '/login/token.php',
      data: {
        'username': username,
        'password': password,
        'service': 'moodle_mobile_app',
      },
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
    final data = response.data;
    if (data == null ||
        data['token'] is! String ||
        (data['token'] as String).isEmpty) {
      throw const SchoolApiException('moodle_authentication_failed');
    }
    return data;
  }

  Future<Object?> read(
    String token,
    String function,
    Map<String, Object> params,
  ) async {
    if (!const {
      'core_webservice_get_site_info',
      'core_enrol_get_users_courses',
      'core_course_get_contents',
      'core_course_get_course_module',
      'mod_forum_get_forums_by_courses',
      'mod_forum_get_forum_discussions',
      'mod_forum_get_discussion_posts',
      'mod_assign_get_assignments',
      'mod_assign_get_submission_status',
      'gradereport_user_get_grade_items',
      'mod_attendance_get_user_sessions',
      'mod_page_get_pages_by_courses',
      'core_message_get_messages',
    }.contains(function)) {
      throw ArgumentError('Unsupported read operation');
    }
    return _call(token, function, params);
  }

  /// Explicit allowlist: never retry a mutation, including draft allocation.
  Future<Object?> mutate(
    String token,
    String function,
    Map<String, Object> params,
  ) {
    if (!const {
      'core_files_get_unused_draft_itemid',
      'mod_assign_save_submission',
      'mod_assign_submit_for_grading',
      'tool_mobile_get_autologin_key',
    }.contains(function)) {
      throw ArgumentError('Unsupported mutation');
    }
    return _call(token, function, params);
  }

  Future<Object?> _call(
    String token,
    String function,
    Map<String, Object> params,
  ) async {
    final response = await http.post<Object?>(
      '/webservice/rest/server.php',
      data: {
        ...params,
        'wstoken': token,
        'wsfunction': function,
        'moodlewsrestformat': 'json',
      },
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
    final data = response.data;
    if (data is Map &&
        (data.containsKey('exception') || data.containsKey('errorcode'))) {
      throw const SchoolApiException('moodle_api_rejected');
    }
    return data;
  }

  Future<Object?> upload(
    String token,
    int itemId,
    String filename,
    List<int> bytes,
  ) async {
    if (bytes.isEmpty) throw const SchoolApiException('empty_file');
    final response = await http.post<Object?>(
      '/webservice/upload.php',
      data: FormData.fromMap({
        'token': token,
        'itemid': '$itemId',
        'component': 'user',
        'filepath': '/',
        'filearea': 'draft',
        'author': 'NIU APP',
        'license': 'allrightsreserved',
        'repo_upload_file': '1',
        'file_1': MultipartFile.fromBytes(
          bytes,
          filename: filename.replaceAll(RegExp(r'[\r\n"]'), '_'),
        ),
      }),
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
    final data = response.data;
    if (data is Map &&
        (data.containsKey('exception') || data.containsKey('error'))) {
      throw const SchoolApiException('moodle_upload_rejected');
    }
    return data;
  }
}
