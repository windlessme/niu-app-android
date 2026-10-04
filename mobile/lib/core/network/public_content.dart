import 'package:dio/dio.dart';

/// Fetches public JSON (calendar, credits) from GitHub raw. Never carries
/// school credentials; injectable so tests stay offline.
typedef PublicContentFetch = Future<List<int>> Function(Uri url);

Future<List<int>> fetchPublicContent(Uri url) async {
  final response = await Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 15),
      responseType: ResponseType.bytes,
      headers: {'Accept': 'application/json'},
    ),
  ).get<List<int>>(url.toString());
  if (response.statusCode != 200 || response.data == null) {
    throw const FormatException('HTTP response');
  }
  return response.data!;
}
