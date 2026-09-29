import 'dart:typed_data';
import 'package:dio/dio.dart';

enum LibraryCodeKind { entrance, borrowing }

class LibraryRepository {
  LibraryRepository(this.http) {
    if (http.options.baseUrl != 'https://sso.niu.edu.tw') {
      throw ArgumentError('Library origin');
    }
  }
  final Dio http;
  Future<Uint8List> image(String account, LibraryCodeKind kind) async {
    account = account.trim().toLowerCase();
    if (account.isEmpty) throw const FormatException('請先登入');
    final Options options = Options(
      responseType: ResponseType.bytes,
      headers: {'Cache-Control': 'no-store'},
    );
    Response<List<int>> response;
    if (kind == LibraryCodeKind.entrance) {
      final number = await http.post<Object?>(
        '/QRCode/Number/',
        data: {'role': 'student', 'acnt': account},
        options: Options(contentType: Headers.jsonContentType),
      );
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
      response = await http.post<List<int>>(
        '/QRCode/Create/Barcode',
        data: {'ou': 'student', 'acnt': account},
        options: options.copyWith(contentType: Headers.jsonContentType),
      );
    }
    final bytes = response.data;
    if (bytes == null || bytes.isEmpty) {
      throw const FormatException('校方未提供有效圖碼');
    }
    return Uint8List.fromList(bytes);
  }
}
