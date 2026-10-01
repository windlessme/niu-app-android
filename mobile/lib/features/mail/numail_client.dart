import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'mail_models.dart';

/// What the 校園信箱 screens need; the school site or the review demo.
abstract interface class MailService {
  /// Account of the live session, or null when signed out.
  Future<String?> signedInAs();
  Future<List<MailFolder>> folders();
  Future<MailPage> list(String box, {int page = 1, String query = ''});
  Future<MailMessage> open(String box, int uid);
  Future<void> setSeen(String box, List<int> uids, bool seen);
  Future<void> move(String box, List<int> uids, String to);

  /// Permanent removal; elsewhere than 垃圾桶/草稿, move to 垃圾桶 instead.
  Future<void> delete(String box, List<int> uids);
  Future<Uint8List> attachment(String box, int uid, MailAttachment file);

  Future<MailDraft> newDraft({String? inReplyTo, List<String> references});
  Future<(MailDraft, MailDraftData)> openDraft(int uid);
  Future<MailAttachment> upload(MailDraft draft, String name, Uint8List bytes);
  Future<MailAttachment> carry(MailDraft draft, MailAttachment original);
  Future<void> detach(MailDraft draft, MailAttachment file);
  Future<void> save(MailDraft draft, MailDraftData data);

  /// Never retried: a lost reply surfaces as [MailUncertain].
  Future<void> send(MailDraft draft, MailDraftData data);
  Future<void> discard(MailDraft draft);

  /// Cookies a WebView needs to show inline pictures of a message.
  Map<String, String> get cookies;
  void close();
}

/// NUMail's JSON API. Cookies stay in this client (and the vault envelope);
/// passwords are only base64-wrapped for the login call, as the site does.
class NumailClient implements MailService {
  NumailClient({Dio? dio, Map<String, String>? cookies})
    : dio = dio ?? _client(),
      jar = {...?cookies} {
    jar.putIfAbsent('XSRF-TOKEN', _token);
  }

  static const host = 'ms.niu.edu.tw';
  static const origin = 'https://$host';
  final Dio dio;
  final Map<String, String> jar;

  @override
  Map<String, String> get cookies => Map.unmodifiable(jar);

  static Dio _client() => Dio(
    BaseOptions(
      baseUrl: origin,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 40),
      sendTimeout: const Duration(seconds: 120),
      followRedirects: false,
      validateStatus: (_) => true,
      responseType: ResponseType.bytes,
    ),
  );

  static String _token() {
    final r = Random.secure();
    return List.generate(32, (_) => r.nextInt(16).toRadixString(16)).join();
  }

  void _take(Response<Object?> response) {
    for (final header in response.headers['set-cookie'] ?? const <String>[]) {
      final m = RegExp(r'^([^=;\s]+)=([^;]*)').firstMatch(header);
      if (m == null) continue;
      final expired = RegExp(
        r'expires=Thu, 01 Jan 1970|max-age=0',
        caseSensitive: false,
      ).hasMatch(header);
      if (expired || m[2]!.isEmpty) {
        jar.remove(m[1]);
      } else {
        jar[m[1]!] = m[2]!;
      }
    }
  }

  Future<Response<List<int>>> _send(
    String method,
    String path, {
    Object? data,
    Map<String, Object?>? query,
    bool login = false,
    bool change = false,
    String accept = 'application/json',
  }) async {
    final Response<List<int>> response;
    try {
      response = await dio.request<List<int>>(
        '/api$path',
        data: data,
        queryParameters: query,
        options: Options(
          method: method,
          contentType: data is FormData ? null : Headers.jsonContentType,
          headers: {
            'Accept': accept,
            'Origin': origin,
            'Referer': '$origin/NUMail/Mobile/Box/INBOX',
            'X-XSRF-TOKEN': Uri.decodeComponent(jar['XSRF-TOKEN'] ?? ''),
            'Cookie': [
              for (final e in jar.entries) '${e.key}=${e.value}',
            ].join('; '),
          },
        ),
      );
    } on DioException catch (e) {
      if (change && e.type != DioExceptionType.connectionError) {
        throw const MailUncertain();
      }
      throw const MailException('無法連線到學校信箱，請檢查網路後再試。');
    }
    _take(response);
    final status = response.statusCode ?? 0;
    if (status >= 200 && status < 300) return response;
    final reason = _reason(response).toLowerCase();
    if (login) {
      if (reason.contains('validation') || reason.contains('captcha')) {
        throw const MailWrongCaptcha();
      }
      if (reason == 'two factor authentication require') {
        throw const MailTwoFactorRequired();
      }
      if (reason == 'please change password first' ||
          reason == 'ad password expired') {
        throw const MailMoreVerification();
      }
      if (reason == 'unauthorized' || status == 401 || status == 403) {
        throw const MailWrongPassword();
      }
    }
    if (status == 401 || status == 403 || (status >= 300 && status < 400)) {
      throw const MailSignInRequired();
    }
    if (change && status >= 500) throw const MailUncertain();
    if (reason == 'quota exceed limit') {
      throw const MailException('信箱空間已滿，請先刪除一些信件。');
    }
    throw MailException('學校信箱暫時無法使用（$status），請稍後再試。');
  }

  static String _reason(Response<List<int>> response) {
    try {
      final body = jsonDecode(utf8.decode(response.data ?? const [])) as Map;
      final error = body['error'];
      return '${error is Map ? error['message'] : body['message'] ?? ''}';
    } catch (_) {
      return '';
    }
  }

  Future<Object?> _json(
    String method,
    String path, {
    Object? data,
    Map<String, Object?>? query,
    bool login = false,
    bool change = false,
  }) async {
    final response = await _send(
      method,
      path,
      data: data,
      query: query,
      login: login,
      change: change,
    );
    final bytes = response.data ?? const <int>[];
    if (bytes.isEmpty) return null;
    try {
      return jsonDecode(utf8.decode(bytes));
    } catch (_) {
      if (change) return null;
      throw const MailException('學校信箱回應格式已變更');
    }
  }

  // ── Sign-in ──

  /// SVG of a sign-in code, or null when the site asks for none.
  Future<String?> captcha() async {
    final config = await _json('GET', '/config/NUMail');
    if (config is Map && config['LOGIN_NEED_VERIFICATION_CODE'] != true) {
      return null;
    }
    final response = await _send(
      'GET',
      '/auth/captcha',
      accept: 'image/svg+xml',
    );
    final svg = utf8.decode(response.data ?? const [], allowMalformed: true);
    if (svg.length > 256000 || !svg.contains('<svg')) {
      throw const MailException('驗證碼格式無法辨識');
    }
    return svg;
  }

  Future<void> login(String account, String password, String captcha) async {
    await _json(
      'POST',
      '/auth/login',
      login: true,
      data: {
        'username': account.trim().toLowerCase(),
        'password': base64.encode(utf8.encode(password)),
        if (captcha.isNotEmpty) 'captcha': captcha,
      },
    );
    await _verify(account);
  }

  Future<void> twoFactor(String account, String code) async {
    try {
      await _json(
        'POST',
        '/auth/2FA/validate',
        login: true,
        data: {'token': code.trim()},
      );
    } on MailWrongPassword {
      throw const MailException('二次驗證碼不正確。');
    } on MailWrongCaptcha {
      throw const MailException('二次驗證碼不正確。');
    }
    await _verify(account);
  }

  // A 2xx login alone does not prove a usable session.
  Future<void> _verify(String account) async {
    final who = await signedInAs();
    if (who == null) throw const MailSignInRequired();
    if (who.toLowerCase() != account.trim().toLowerCase()) {
      throw const MailException('信箱帳號和 App 登入的帳號不同。');
    }
  }

  @override
  Future<String?> signedInAs() async {
    try {
      final user = await _json('GET', '/auth/user');
      final name = user is Map ? '${user['username'] ?? ''}'.trim() : '';
      return name.isEmpty ? null : name;
    } on MailSignInRequired {
      return null;
    }
  }

  // ── Reading ──

  @override
  Future<List<MailFolder>> folders() async {
    final data = await _json('GET', '/box');
    final boxes = data is Map ? data['boxes'] : null;
    final list = <MailFolder>[];
    void walk(Object? node, String prefix) {
      if (node is! Map) return;
      for (final MapEntry(:key, :value) in node.entries) {
        if (value is! Map) continue;
        final name = prefix.isEmpty ? '$key' : '$prefix/$key';
        final attributes = [
          if (value['attribs'] is List)
            for (final a in value['attribs'] as List) '$a',
        ];
        if (!attributes.any((a) => a.contains('Noselect'))) {
          list.add(
            MailFolder(
              name,
              unseen: value['unseen'] is int ? value['unseen'] as int : 0,
              attributes: attributes,
            ),
          );
        }
        walk(value['children'], name);
      }
    }

    walk(boxes, '');
    if (list.isEmpty) throw const MailException('讀不到信件匣');
    return list..sort((a, b) {
      final byOrder = a.order - b.order;
      return byOrder != 0 ? byOrder : a.label.compareTo(b.label);
    });
  }

  @override
  Future<MailPage> list(String box, {int page = 1, String query = ''}) async {
    final searching = query.trim().isNotEmpty;
    final data = await _json(
      'GET',
      searching ? '/mails/search' : '/mails/box/${encodeBox(box)}',
      query: {
        'page': page,
        'sort': 'date',
        'asc': false,
        if (searching) ...{'all': query.trim(), 'box': encodeBox(box)},
      },
    );
    if (data is! Map || data['mails'] is! List) {
      throw const MailException('學校信箱回應格式已變更');
    }
    return MailPage(
      [
        for (final m in data['mails'] as List)
          if (m is Map) MailSummary.fromJson(m, box),
      ],
      data['total'] is int ? data['total'] as int : 0,
      page,
    );
  }

  @override
  Future<MailMessage> open(String box, int uid) async {
    final data = await _json('GET', '/mails/box/${encodeBox(box)}/$uid');
    final group = data is Map ? data['mailGroup'] : null;
    if (group is! List || group.isEmpty || group.first is! Map) {
      throw const MailException('找不到這封信，可能已被移動或刪除。');
    }
    final message = MailMessage.fromJson(group.first as Map);
    return message.box.isEmpty
        ? MailMessage.fromJson({...group.first as Map, 'box': box})
        : message;
  }

  @override
  Future<void> setSeen(String box, List<int> uids, bool seen) => seen
      ? _json(
          'POST',
          '/mails/box/${encodeBox(box)}/${uids.join(',')}/flags',
          data: {
            'flags': ['Seen'],
          },
        )
      : _json(
          'DELETE',
          '/mails/box/${encodeBox(box)}/${uids.join(',')}/flags/Seen',
        );

  @override
  Future<void> move(String box, List<int> uids, String to) => _json(
    'POST',
    '/mails/box/${encodeBox(box)}/${uids.join(',')}/move',
    data: {'dstBox': to},
  );

  @override
  Future<void> delete(String box, List<int> uids) =>
      _json('DELETE', '/mails/box/${encodeBox(box)}/${uids.join(',')}');

  @override
  Future<Uint8List> attachment(String box, int uid, MailAttachment file) async {
    final response = await _send(
      'GET',
      '/mails/box/${encodeBox(box)}/$uid/attachment/${file.partId}',
      accept: '*/*',
    );
    return Uint8List.fromList(response.data ?? const []);
  }

  // ── Writing ──

  @override
  Future<MailDraft> newDraft({
    String? inReplyTo,
    List<String> references = const [],
  }) async {
    final data = await _json(
      'POST',
      '/draft',
      data: {
        'inReplyTo': ?inReplyTo,
        if (references.isNotEmpty) 'references': references,
      },
    );
    final id = data is Map ? data['id'] : null;
    if (id == null || '$id'.isEmpty) throw const MailException('無法建立草稿');
    return MailDraft('$id');
  }

  @override
  Future<(MailDraft, MailDraftData)> openDraft(int uid) async {
    final data = await _json('GET', '/draft/uid/$uid');
    if (data is! Map || data['id'] == null) {
      throw const MailException('無法開啟這份草稿');
    }
    final html = '${data['body'] ?? ''}';
    final attachments = [
      if (data['attachments'] is List)
        for (final a in data['attachments'] as List)
          if (a is Map) MailAttachment.fromJson(a),
    ];
    return (
      MailDraft('${data['id']}', attachments: attachments),
      MailDraftData(
        to: addressList(data['receiver']),
        cc: addressList(data['cc']),
        bcc: addressList(data['bcc']),
        subject: '${data['subject'] ?? ''}',
        text: htmlToText(html),
        type: data['type'] is String ? data['type'] as String : null,
      ),
    );
  }

  @override
  Future<MailAttachment> upload(
    MailDraft draft,
    String name,
    Uint8List bytes,
  ) async {
    final data = await _json(
      'POST',
      '/draft/${draft.id}/attachments',
      data: FormData.fromMap({
        'file': MultipartFile.fromBytes(bytes, filename: name),
      }),
    );
    if (data is! Map) throw const MailException('附件上傳失敗');
    return MailAttachment.fromJson({'filename': name, ...data});
  }

  @override
  Future<MailAttachment> carry(MailDraft draft, MailAttachment original) async {
    final data = await _json(
      'POST',
      '/draft/${draft.id}/attachments/append',
      data: {'attachmentId': original.id, 'cid': original.cid},
    );
    return data is Map
        ? MailAttachment.fromJson({
            'filename': original.filename,
            'size': original.size,
            ...data,
          })
        : original;
  }

  @override
  Future<void> detach(MailDraft draft, MailAttachment file) =>
      _json('DELETE', '/draft/${draft.id}/attachments/${file.id}');

  @override
  Future<void> save(MailDraft draft, MailDraftData data) =>
      _json('POST', '/draft/${draft.id}/save', data: data.toJson());

  @override
  Future<void> send(MailDraft draft, MailDraftData data) => _json(
    'POST',
    '/draft/${draft.id}/send',
    data: data.toJson(),
    change: true,
  );

  @override
  Future<void> discard(MailDraft draft) =>
      _json('DELETE', '/draft/${draft.id}');

  @override
  void close() => dio.close(force: true);
}

/// Rough plain text of a draft body for editing.
String htmlToText(String html) => html
    .replaceAll(RegExp(r'<head[\s\S]*?</head>', caseSensitive: false), '')
    .replaceAll(RegExp(r'<style[\s\S]*?</style>', caseSensitive: false), '')
    .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
    .replaceAll(RegExp(r'</(p|div|li|tr|h\d)>', caseSensitive: false), '\n')
    .replaceAll(RegExp(r'<[^>]+>'), '')
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAllMapped(
      RegExp(r'&#(x?)([0-9a-fA-F]+);'),
      (m) => String.fromCharCode(
        int.tryParse(m[2]!, radix: m[1]!.isEmpty ? 10 : 16) ?? 0x20,
      ),
    )
    .replaceAll('&amp;', '&')
    .replaceAll(RegExp(r'\n{3,}'), '\n\n')
    .trim();
