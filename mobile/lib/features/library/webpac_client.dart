import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:pointycastle/export.dart';

import '../../core/time/campus_date.dart';
import 'space_models.dart';

/// The library catalogue (凌網 HyLib WebPAC) at webpacx. Its GraphQL endpoint
/// needs the HYSESSION cookie plus the page's CSRF token. Accounts and
/// passwords are the school ones, encrypted the way the site's login form does.
class WebpacClient implements SpaceService {
  WebpacClient({Dio? dio, this.session}) : dio = dio ?? _client();
  static const origin = 'https://webpacx.niu.edu.tw';
  final Dio dio;

  /// HYSESSION value; null until the site issues one.
  String? session;
  String? _csrf;

  static Dio _client() => Dio(
    BaseOptions(
      baseUrl: origin,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 25),
      followRedirects: false,
      validateStatus: (_) => true,
      responseType: ResponseType.plain,
    ),
  );

  Map<String, String> get _cookie => {
    if (session != null) 'Cookie': 'HYSESSION=$session',
  };

  void _takeCookie(Response<Object?> response) {
    for (final header in response.headers['set-cookie'] ?? const <String>[]) {
      final m = RegExp(r'^HYSESSION=([^;]*)').firstMatch(header);
      if (m != null && m[1]!.isNotEmpty) session = m[1];
    }
  }

  /// Loads a page to pick up the session and CSRF token; true when signed in.
  Future<bool> page() async {
    final response = await dio.get<String>(
      '/equipment',
      options: Options(headers: _cookie),
    );
    _takeCookie(response);
    if (response.statusCode != 200) {
      throw const SpaceException('圖書館系統暫時無法使用，稍後再試。');
    }
    final body = response.data ?? '';
    final token = RegExp(r'"csrfToken":"([^"]+)"').firstMatch(body)?[1];
    if (token == null) throw const SpaceException('圖書館系統格式已變更');
    _csrf = token;
    return RegExp(r'"auth":true').hasMatch(body);
  }

  Future<Map<String, dynamic>> query(
    String document, [
    Map<String, Object?> variables = const {},
  ]) async {
    if (_csrf == null) await page();
    for (var attempt = 0; ; attempt++) {
      final response = await dio.post<String>(
        '/api/HyLibWS/graphql',
        data: jsonEncode({'query': document, 'variables': variables}),
        options: Options(
          contentType: Headers.jsonContentType,
          headers: {..._cookie, 'X-CSRF-Token': _csrf},
        ),
      );
      _takeCookie(response);
      // A stale CSRF token is rejected before the operation runs.
      if (response.statusCode == 403 && attempt == 0) {
        await page();
        continue;
      }
      if (response.statusCode != 200) {
        throw const SpaceException('圖書館系統暫時無法使用，稍後再試。');
      }
      final body = jsonDecode(response.data ?? '') as Map<String, dynamic>;
      final data = body['data'];
      if (data is! Map<String, dynamic>) {
        throw const SpaceException('圖書館系統回應格式已變更');
      }
      return data;
    }
  }

  /// Signs in with the school account; returns the new HYSESSION.
  Future<String> login(String account, String password) async {
    session = null;
    _csrf = null;
    await page();
    final data = await query(
      r'''
mutation($user: String!, $pass: String!) {
  ssoLogin(user: $user, pass: $pass, captcha: "", encrypt: true) {
    success message errorType
    loginChooseReaderList { readerId readerCode }
  }
}''',
      {
        'user': encryptCredential(account.trim()),
        'pass': encryptCredential(password),
      },
    );
    final result = data['ssoLogin'] as Map<String, dynamic>? ?? const {};
    if (result['success'] != true) {
      // 3: one ID maps to several library cards; take the student's own.
      final cards = result['loginChooseReaderList'];
      if (result['errorType'] == 3 && cards is List && cards.isNotEmpty) {
        final own = cards.cast<Map>().firstWhere(
          (c) =>
              '${c['readerCode']}'.toLowerCase() ==
              account.trim().toLowerCase(),
          orElse: () => cards.first as Map,
        );
        final chosen = await query(
          r'mutation($id: Int!) { ssoChooseLogin(readerId: $id) { success message } }',
          {'id': own['readerId']},
        );
        if (chosen['ssoChooseLogin']?['success'] != true) {
          throw SpaceException(_loginMessage(chosen['ssoChooseLogin']));
        }
      } else {
        throw SpaceException(_loginMessage(result));
      }
    }
    if (!await page() || session == null) {
      throw const SpaceException('圖書館登入沒有完成，請稍後再試。');
    }
    return session!;
  }

  static String _loginMessage(Object? result) {
    final message = result is Map ? '${result['message'] ?? ''}' : '';
    return message.isEmpty || message.contains(':')
        ? '圖書館登入失敗，請確認帳號密碼。'
        : message;
  }

  @override
  Future<List<SpaceGroup>> groups() async {
    final data = await query('''
{ getEquipmentGroupInfo { eqgroupitemlist {
  equipmentGroup { id name webpacDisplay }
  ebPolicy { id }
} } }''');
    // Groups without a policy for this reader (e.g. 長期研究小間) are not
    // bookable online.
    return [
      for (final item in _items(data['getEquipmentGroupInfo']))
        if (item['equipmentGroup'] case final Map g
            when g['webpacDisplay'] != 0 &&
                g['id'] is int &&
                item['ebPolicy'] != null)
          SpaceGroup(g['id'] as int, '${g['name']}'.trim()),
    ];
  }

  @override
  Future<SpaceDay> day(SpaceGroup group, CampusDate date) async {
    final data = await query(
      r'''
query($g: Int, $d: String) {
  getEquipmentInfoList(groupId: $g) { eqgroupitemlist { equipment { id name } } }
  getReserveEquipmentList(groupId: $g, startdate: $d) { eqgroupitemlist {
    reserveCountByUser equipmentCir { equipmentId startDate endDate }
  } }
}''',
      {'g': group.id, 'd': webpacDate(date)},
    );
    final rooms = [
      for (final item in _items(data['getEquipmentInfoList']))
        if (item['equipment'] case final Map e when e['id'] is int)
          SpaceRoom(e['id'] as int, '${e['name']}'.trim()),
    ];
    final seen = <String>{};
    final bookings = <SpaceBooking>[];
    for (final item in _items(data['getReserveEquipmentList'])) {
      final cir = item['equipmentCir'];
      if (cir is! Map || cir['equipmentId'] is! int) continue;
      final key = '${cir['equipmentId']}|${cir['startDate']}|${cir['endDate']}';
      if (!seen.add(key)) continue;
      final booking = SpaceDay.clip(
        date,
        cir['equipmentId'] as int,
        cir['startDate'] as String?,
        cir['endDate'] as String?,
        item['reserveCountByUser'] == 1,
      );
      if (booking != null) bookings.add(booking);
    }
    if (rooms.isEmpty) throw const SpaceException('這個類別目前沒有開放的空間');
    // The policy is per group, but the site asks through one of its rooms.
    final policy = (await query(
      r'''
query($q: Int, $g: Int, $d: String) {
  getDayReservedByReader(equipId: $q, groupId: $g, reserveDate: $d) { success data message }
}''',
      {'q': rooms.first.id, 'g': group.id, 'd': webpacDate(date)},
    ))['getDayReservedByReader'];
    final message = policy is Map ? '${policy['message'] ?? ''}' : '';
    if (policy is! Map || policy['data'] is! String) {
      throw SpaceException(
        message.isEmpty || message.contains(':') ? '無法取得預約規則' : message,
      );
    }
    return SpaceDay(
      group: group,
      date: date,
      rooms: rooms,
      bookings: bookings,
      rules: SpaceRules.parse(policy['data'] as String),
    );
  }

  @override
  Future<List<SpaceReservation>> mine() async {
    final data = await query('''
{
  reserve: getEquipmentByReader(status: "Reserve") { success eqgroupitemlist {
    equipment { name }
    equipmentCir { reserveKeepDate }
    equipmentCirContent { id startDate endDate }
  } }
  borrow: getEquipmentByReader(status: "Borrow") { success eqgroupitemlist {
    equipment { name }
    equipmentCirContent { id startDate endDate }
  } }
}''');
    final list = <SpaceReservation>[];
    for (final (key, state) in [
      ('borrow', ReservationState.inUse),
      ('reserve', ReservationState.reserved),
    ]) {
      for (final item in _items(data[key])) {
        final content = item['equipmentCirContent'];
        if (content is! Map || content['id'] is! int) continue;
        final start = parseStamp(content['startDate'] as String?);
        final end = parseStamp(content['endDate'] as String?);
        if (start == null || end == null) continue;
        final keep = parseStamp(
          (item['equipmentCir'] as Map?)?['reserveKeepDate'] as String?,
        );
        list.add(
          SpaceReservation(
            id: content['id'] as int,
            roomName: '${(item['equipment'] as Map?)?['name'] ?? '空間'}'.trim(),
            date: start.$1,
            start: start.$2,
            endDate: end.$1,
            end: end.$2,
            state: state,
            keepUntil: keep?.$2,
          ),
        );
      }
    }
    return list;
  }

  @override
  Future<void> reserve(
    SpaceGroup group,
    SpaceRoom room,
    CampusDate date,
    Minute start,
    Minute end,
  ) async {
    final day = webpacDate(date);
    final data = await query(
      r'''
mutation($s: String, $e: String, $q: Int, $g: Int) {
  reserveEquipmentCir(starttime: $s, endtime: $e, equipId: $q, groupId: $g, muserid: 100) {
    success message
  }
}''',
      {
        's': '$day ${formatMinute(start)}',
        'e': '$day ${formatMinute(end)}',
        'q': room.id,
        'g': group.id,
      },
    );
    final result = data['reserveEquipmentCir'];
    if (result is! Map || result['success'] != true) {
      throw SpaceException(
        describeReserveFailure(
          result is Map ? result['message'] as String? : null,
        ),
      );
    }
  }

  @override
  Future<void> cancel(SpaceReservation reservation) async {
    final data = await query(
      r'mutation($i: Int) { cancelEquipmentCir(eccId: $i, eccIds: "") { success message } }',
      {'i': reservation.id},
    );
    final result = data['cancelEquipmentCir'];
    if (result is! Map || result['success'] != true) {
      throw const SpaceException('取消沒有成功，請重新整理後再試。');
    }
  }

  @override
  void close() => dio.close(force: true);

  static Iterable<Map> _items(Object? block) sync* {
    if (block is! Map) return;
    final list = block['eqgroupitemlist'];
    if (list is! List) return;
    for (final item in list) {
      if (item is Map) yield item;
    }
  }
}

/// AES-256-CBC with the site's fixed key, as `ivHex:base64Ciphertext` —
/// the format of CryptoJS.AES.encrypt in the site's login form.
String encryptCredential(String text, {Uint8List? iv}) {
  final key = _hex(
    'a20b070dfdf921334a47ee5c076106068c718f11e97e4835e08acf19b6728684',
  );
  final vector = iv ?? _randomBytes(16);
  final cipher =
      PaddedBlockCipherImpl(PKCS7Padding(), CBCBlockCipher(AESEngine()))..init(
        true,
        PaddedBlockCipherParameters<CipherParameters, CipherParameters>(
          ParametersWithIV(KeyParameter(key), vector),
          null,
        ),
      );
  final encrypted = cipher.process(Uint8List.fromList(utf8.encode(text)));
  final ivHex = vector.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '$ivHex:${base64.encode(encrypted)}';
}

Uint8List _hex(String hex) => Uint8List.fromList([
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
]);

Uint8List _randomBytes(int length) {
  final random = Random.secure();
  return Uint8List.fromList([
    for (var i = 0; i < length; i++) random.nextInt(256),
  ]);
}
