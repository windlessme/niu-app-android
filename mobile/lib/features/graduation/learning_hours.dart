import 'dart:convert';

import 'package:dio/dio.dart';

import '../../core/session/campus_session.dart';
import '../authentication/remember_school_login.dart';

/// One domain total from `/Api/MultLearn`, e.g. 服務奉獻 2 / 20.
class LearningHoursSummary {
  const LearningHoursSummary({
    required this.abilityId,
    required this.ability,
    required this.earned,
    required this.required,
  });
  factory LearningHoursSummary.fromJson(Map<String, dynamic> json) =>
      LearningHoursSummary(
        abilityId: json['abilityId'].toString(),
        ability: json['ability'].toString(),
        earned: (json['earned'] as num).toDouble(),
        required: (json['required'] as num).toDouble(),
      );
  final String abilityId, ability;
  final double earned, required;
  Map<String, dynamic> toJson() => {
    'abilityId': abilityId,
    'ability': ability,
    'earned': earned,
    'required': required,
  };
}

/// One certified activity from `/Api/MultLearnDetail`, in the school's own
/// wording (dates look like `2024/9/3`).
class LearningHoursRecord {
  const LearningHoursRecord({
    required this.startDate,
    required this.endDate,
    required this.title,
    required this.ability,
    required this.hours,
  });
  factory LearningHoursRecord.fromJson(Map<String, dynamic> json) =>
      LearningHoursRecord(
        startDate: json['startDate'].toString(),
        endDate: json['endDate'].toString(),
        title: json['title'].toString(),
        ability: json['ability'].toString(),
        hours: json['hours'].toString(),
      );
  final String startDate, endDate, title, ability, hours;
  String get dates =>
      startDate == endDate ? startDate : '$startDate – $endDate';
  Map<String, dynamic> toJson() => {
    'startDate': startDate,
    'endDate': endDate,
    'title': title,
    'ability': ability,
    'hours': hours,
  };
}

class LearningHoursSnapshot {
  const LearningHoursSnapshot({
    required this.summaries,
    required this.records,
    required this.fetchedAt,
  });
  factory LearningHoursSnapshot.fromJson(Map<String, dynamic> json) =>
      LearningHoursSnapshot(
        summaries: [
          for (final item in json['summaries'] as List)
            LearningHoursSummary.fromJson(Map<String, dynamic>.from(item)),
        ],
        records: [
          for (final item in json['records'] as List)
            LearningHoursRecord.fromJson(Map<String, dynamic>.from(item)),
        ],
        fetchedAt: DateTime.parse(json['fetchedAt'] as String),
      );
  final List<LearningHoursSummary> summaries;
  final List<LearningHoursRecord> records;
  final DateTime fetchedAt;
  Map<String, dynamic> toJson() => {
    'summaries': [for (final s in summaries) s.toJson()],
    'records': [for (final r in records) r.toJson()],
    'fetchedAt': fetchedAt.toUtc().toIso8601String(),
  };
}

class LearningHoursException implements Exception {
  const LearningHoursException(this.message, this.reason);
  final String message;

  /// Fixed code for analytics.
  final String reason;

  static const credentialsMissing = LearningHoursException(
    '找不到已儲存的登入資訊，請重新登入 App 後再試。',
    'credentials_missing',
  );
  static const invalidCredentials = LearningHoursException(
    '學生服務平台登入失敗，請確認帳號密碼；若最近改過密碼，請重新登入 App。',
    'credentials',
  );
  static const campusNetworkRequired = LearningHoursException(
    '無法連線至學生服務平台，請連接校園網路後再更新。',
    'campus_network',
  );
  static const offline = LearningHoursException('目前沒有網路連線，請連線後重試。', 'offline');
  static const sessionExpired = LearningHoursException(
    '學生服務平台登入已逾時，請稍後重試。',
    'expired',
  );
  static const invalidResponse = LearningHoursException(
    '無法辨識學生服務平台的資料格式，請稍後重試。',
    'format',
  );
  static const tooManyPages = LearningHoursException(
    '時數紀錄頁數異常，已停止讀取，請稍後重試。',
    'pages',
  );

  @override
  String toString() => message;
}

/// Hours as the school writes them: `2`, `1.5`.
String formatLearningHours(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toStringAsFixed(1);

abstract final class LearningHoursParser {
  /// Same order as the graduation card: 服務、多元、專業、綜合.
  static const abilityOrder = ['1', '2', '3', '99'];

  static int _order(String id) {
    final index = abilityOrder.indexOf(id);
    return index < 0 ? abilityOrder.length : index;
  }

  static double? _number(Object? value) => switch (value) {
    num() => value.toDouble(),
    String() => double.tryParse(value.trim()),
    _ => null,
  };

  /// The API answers `[]` instead of an error when the session cookie is
  /// missing or expired, so an array root means "not signed in".
  static List<LearningHoursSummary> summary(String body) {
    Object? root;
    try {
      root = jsonDecode(body);
    } catch (_) {
      throw LearningHoursException.invalidResponse;
    }
    if (root is List) throw LearningHoursException.sessionExpired;
    if (root is! Map) throw LearningHoursException.invalidResponse;
    if (root['IsSuccess'] != true) {
      final message = root['Message']?.toString().trim() ?? '';
      throw message.isEmpty
          ? LearningHoursException.invalidResponse
          : LearningHoursException('學生服務平台回報錯誤：$message', 'school_error');
    }
    final items = root['Data'] ?? const [];
    if (items is! List) throw LearningHoursException.invalidResponse;
    final summaries = <LearningHoursSummary>[];
    for (final item in items) {
      if (item is! Map) throw LearningHoursException.invalidResponse;
      final earned = _number(item['CaHr']);
      final required = _number(item['TCaHr']);
      final id = item['AbilityId'];
      if (earned == null || required == null || id == null) {
        throw LearningHoursException.invalidResponse;
      }
      summaries.add(
        LearningHoursSummary(
          abilityId: id is num && id == id.roundToDouble()
              ? id.toInt().toString()
              : id.toString(),
          ability: item['Ability']?.toString() ?? '',
          earned: earned,
          required: required,
        ),
      );
    }
    return summaries
      ..sort((a, b) => _order(a.abilityId).compareTo(_order(b.abilityId)));
  }

  static final _cell = RegExp(
    r'class="learninghours__td"[^>]*>([\s\S]*?)</div>',
  );
  static final _pageLink = RegExp(r'[?&]page=(\d+)');
  static final _pageButton = RegExp(r'paging__btn[^"]*"[^>]*>\s*(\d+)\s*<');

  static ({List<LearningHoursRecord> records, int lastPage}) detail(
    String html,
  ) {
    if (html.contains('登入逾時') || html.contains('location.replace')) {
      throw LearningHoursException.sessionExpired;
    }
    final paging = html.indexOf('id="page_html"');
    if (paging < 0) throw LearningHoursException.invalidResponse;
    final body = html.substring(0, paging);
    final pager = html.substring(paging);
    final records = <LearningHoursRecord>[];
    for (final chunk in body.split('learninghours__tbody-row').skip(1)) {
      final cells = [
        for (final match in _cell.allMatches(chunk)) cleanText(match[1]!),
      ];
      if (cells.length < 5) throw LearningHoursException.invalidResponse;
      records.add(
        LearningHoursRecord(
          startDate: cells[0],
          endDate: cells[1],
          title: cells[2],
          ability: cells[3],
          hours: cells[4],
        ),
      );
    }
    final pages = [
      for (final m in _pageLink.allMatches(pager)) int.parse(m[1]!),
      for (final m in _pageButton.allMatches(pager)) int.parse(m[1]!),
    ];
    final last = pages.fold(1, (a, b) => b > a ? b : a);
    return (records: records, lastPage: last);
  }

  static String cleanText(String raw) {
    var text = raw.replaceAll(RegExp(r'<[^>]+>'), '');
    const entities = {
      '&nbsp;': ' ',
      '&lt;': '<',
      '&gt;': '>',
      '&quot;': '"',
      '&#39;': "'",
      '&apos;': "'",
    };
    entities.forEach((entity, value) => text = text.replaceAll(entity, value));
    text = text.replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
      final code = int.tryParse(m[1]!);
      return code == null || code > 0x10FFFF
          ? m[0]!
          : String.fromCharCode(code);
    });
    text = text.replaceAll('&amp;', '&');
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}

/// Signs in to the student portal (ep.niu.edu.tw), which answers on the
/// campus network only, and reads 多元學習認證 hours. Each fetch uses its own
/// client and cookies, so the portal session never outlives it.
class LearningHoursClient {
  LearningHoursClient({Dio Function()? dio}) : _dio = dio ?? _client;
  final Dio Function() _dio;
  static final base = Uri.https('ep.niu.edu.tw', '/');
  static final pageUrl = base.resolve('/search/learning_certification');
  static const maxPages = 30;

  static Dio _client() => Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      followRedirects: false,
      responseType: ResponseType.plain,
      validateStatus: (_) => true,
    ),
  );

  Future<LearningHoursSnapshot> fetch(String account, String password) async {
    final dio = _dio();
    final cookies = <String, String>{};
    try {
      final login = await _send(
        dio,
        cookies,
        base.resolve('/login/student'),
        form: {'student_id': account, 'password': password},
        referer: base.resolve('/login'),
      );
      Object? json;
      try {
        json = jsonDecode(login);
      } catch (_) {}
      if (json is! Map) throw LearningHoursException.invalidResponse;
      final status = json['status'];
      if (status != 1 && status != '1') {
        throw LearningHoursException.invalidCredentials;
      }
      final summaries = LearningHoursParser.summary(
        await _send(dio, cookies, base.resolve('/Api/MultLearn')),
      );
      final records = <LearningHoursRecord>[];
      var page = 1;
      var lastPage = 1;
      while (page <= lastPage) {
        final parsed = LearningHoursParser.detail(
          await _send(
            dio,
            cookies,
            base.resolve('/Api/MultLearnDetail?page=$page'),
          ),
        );
        if (parsed.lastPage > maxPages) {
          throw LearningHoursException.tooManyPages;
        }
        if (parsed.records.isEmpty) break;
        records.addAll(parsed.records);
        lastPage = parsed.lastPage;
        page++;
      }
      return LearningHoursSnapshot(
        summaries: summaries,
        records: records,
        fetchedAt: DateTime.now(),
      );
    } finally {
      dio.close(force: true);
    }
  }

  Future<String> _send(
    Dio dio,
    Map<String, String> cookies,
    Uri url, {
    Map<String, String>? form,
    Uri? referer,
  }) async {
    final headers = {
      'X-Requested-With': 'XMLHttpRequest',
      'Referer': '${referer ?? pageUrl}',
      if (cookies.isNotEmpty)
        'Cookie': cookies.entries.map((e) => '${e.key}=${e.value}').join('; '),
    };
    final Response<String> response;
    try {
      response = form == null
          ? await dio.get<String>('$url', options: Options(headers: headers))
          : await dio.post<String>(
              '$url',
              data: form,
              options: Options(
                headers: headers,
                contentType: Headers.formUrlEncodedContentType,
              ),
            );
    } on DioException {
      // Timeouts, refused connections and DNS failures are what an
      // off-campus phone sees; the portal has no public address.
      throw LearningHoursException.campusNetworkRequired;
    }
    for (final header in response.headers['set-cookie'] ?? const <String>[]) {
      final pair = header.split(';').first;
      final split = pair.indexOf('=');
      if (split > 0) {
        cookies[pair.substring(0, split).trim()] = pair
            .substring(split + 1)
            .trim();
      }
    }
    final status = response.statusCode ?? 0;
    if (status == 401 || status == 403) {
      throw LearningHoursException.campusNetworkRequired;
    }
    if (status < 200 || status >= 300) {
      throw LearningHoursException.invalidResponse;
    }
    return response.data ?? '';
  }
}

/// The last snapshot that loaded, kept in the session's secure storage with
/// its account: the portal needs the campus network, so this is what shows
/// most of the time. Cleared on logout with the rest of the store.
class LearningHoursStore {
  LearningHoursStore(this.session, {LearningHoursClient? client})
    : client = client ?? LearningHoursClient();
  final CampusSession session;
  final LearningHoursClient client;
  static const key = 'learningHoursCache';

  Future<LearningHoursSnapshot?> cached() async {
    if (session.isDemo) return demoSnapshot();
    final owner = session.account;
    if (owner == null) return null;
    try {
      final raw = await session.vault.read(key);
      final data = raw == null || raw.isEmpty ? null : jsonDecode(raw);
      if (data is Map && data['account'] == owner && data['snapshot'] is Map) {
        return LearningHoursSnapshot.fromJson(
          Map<String, dynamic>.from(data['snapshot'] as Map),
        );
      }
    } catch (_) {
      // A damaged copy counts as none.
    }
    return null;
  }

  /// Fetches with the remembered school password and saves the result.
  /// Returns null when the account changed while loading.
  Future<LearningHoursSnapshot?> refresh() async {
    if (session.isDemo) return demoSnapshot();
    final owner = session.account;
    if (owner == null) throw LearningHoursException.credentialsMissing;
    final epoch = session.coordinator.epoch;
    final saved = await RememberSchoolLogin.forSession(session).restore();
    if (saved == null || saved.account.toLowerCase() != owner.toLowerCase()) {
      throw LearningHoursException.credentialsMissing;
    }
    final LearningHoursSnapshot snapshot;
    try {
      snapshot = await client.fetch(saved.account, saved.password);
    } on LearningHoursException catch (error) {
      if (identical(error, LearningHoursException.campusNetworkRequired) &&
          session.isOffline) {
        throw LearningHoursException.offline;
      }
      rethrow;
    }
    // Never save one account's hours after a logout or switch.
    if (session.coordinator.epoch != epoch || session.account != owner) {
      return null;
    }
    await session.vault.write(
      key,
      jsonEncode({'account': owner, 'snapshot': snapshot.toJson()}),
    );
    return snapshot;
  }

  static LearningHoursSnapshot demoSnapshot() => LearningHoursSnapshot(
    summaries: const [
      LearningHoursSummary(
        abilityId: '1',
        ability: '服務奉獻',
        earned: 12,
        required: 20,
      ),
      LearningHoursSummary(
        abilityId: '2',
        ability: '多元學習',
        earned: 9,
        required: 12,
      ),
      LearningHoursSummary(
        abilityId: '3',
        ability: '專業學習',
        earned: 6,
        required: 8,
      ),
    ],
    records: const [
      LearningHoursRecord(
        startDate: '2026/9/16',
        endDate: '2026/9/16',
        title: '新生學習適應講座',
        ability: '多元學習',
        hours: '2',
      ),
      LearningHoursRecord(
        startDate: '2026/5/2',
        endDate: '2026/5/3',
        title: '社區淨灘服務',
        ability: '服務奉獻',
        hours: '8',
      ),
      LearningHoursRecord(
        startDate: '2026/4/22',
        endDate: '2026/4/22',
        title: '資訊安全實務工作坊',
        ability: '專業學習',
        hours: '3',
      ),
      LearningHoursRecord(
        startDate: '2026/3/11',
        endDate: '2026/3/11',
        title: '職涯探索講座',
        ability: '多元學習',
        hours: '1.5',
      ),
    ],
    fetchedAt: DateTime(2026, 10, 1, 9),
  );
}
