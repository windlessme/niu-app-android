import 'dart:typed_data';
import 'package:dio/dio.dart';

enum LibraryCodeKind { entrance, borrowing }

/// The school rejected the SSO token, or none belongs to this account.
class LibraryLoginRequired implements Exception {
  const LibraryLoginRequired();
}

class LibraryRepository {
  LibraryRepository(this.http, {this.token, this.onRejected}) {
    if (http.options.baseUrl != 'https://sso.niu.edu.tw') {
      throw ArgumentError('Library origin');
    }
  }
  final Dio http;

  /// The QRCode API requires the ccsys1 SSO bearer token the portal sends.
  /// Returns null unless the token belongs to [account].
  final String? Function(String account)? token;
  final void Function(String token)? onRejected;

  Future<Response<T>> _post<T>(
    String path,
    String account,
    Map<String, String> body,
    Options options,
  ) async {
    final bearer = token?.call(account);
    if (bearer == null) throw const LibraryLoginRequired();
    try {
      return await http.post<T>(
        path,
        data: body,
        options: options.copyWith(
          contentType: Headers.jsonContentType,
          headers: {
            ...?options.headers,
            'Accept': 'application/json, text/plain, */*',
            'Authorization': 'Bearer $bearer',
            // Header parity with the portal page that calls this API.
            'Origin': 'https://ccsys1.niu.edu.tw',
            'Referer': 'https://ccsys1.niu.edu.tw/',
          },
        ),
      );
    } on DioException catch (error) {
      if ([401, 403].contains(error.response?.statusCode)) {
        onRejected?.call(bearer);
        throw const LibraryLoginRequired();
      }
      rethrow;
    }
  }

  Future<Uint8List> image(String account, LibraryCodeKind kind) async {
    account = account.trim().toLowerCase();
    if (account.isEmpty) throw const FormatException('請先登入');
    final Options options = Options(
      responseType: ResponseType.bytes,
      headers: {'Cache-Control': 'no-store'},
    );
    Response<List<int>> response;
    if (kind == LibraryCodeKind.entrance) {
      final number = await _post<Object?>('/QRCode/Number/', account, {
        'role': 'student',
        'acnt': account,
      }, Options());
      final data = number.data;
      if (data is! Map ||
          data['no'] is! String ||
          (data['no'] as String).trim().isEmpty) {
        throw const FormatException('校方未提供有效通行碼');
      }
      final validation = Uri(
        scheme: 'https',
        host: 'sso.niu.edu.tw',
        pathSegments: ['QRCode', 'Validate', data['no'] as String],
      );
      response = await http.get<List<int>>(
        '/QRCode/Create',
        queryParameters: {'u': '$validation'},
        options: options,
      );
    } else {
      response = await _post<List<int>>('/QRCode/Create/Barcode', account, {
        'ou': 'student',
        'acnt': account,
      }, options);
    }
    final bytes = response.data;
    if (bytes == null || bytes.isEmpty) {
      throw const FormatException('校方未提供有效圖碼');
    }
    return Uint8List.fromList(bytes);
  }
}
