import 'package:dio/dio.dart';

import 'postal_models.dart';

/// Talks to the public school postal lookup. A fresh client per search keeps
/// no cookies between searches and sends no school credentials.
class PostalService {
  PostalService({Dio? dio}) : dio = dio ?? _client();
  final Dio dio;
  static final uri = Uri.https('ccsys2.niu.edu.tw', '/GA/Postal/');

  static Dio _client() => Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 25),
      followRedirects: false,
      responseType: ResponseType.plain,
      validateStatus: (_) => true,
    ),
  );

  Future<String> _request([Map<String, String>? fields]) async {
    final response = fields == null
        ? await dio.get<String>('$uri')
        : await dio.post<String>(
            '$uri',
            data: fields,
            options: Options(contentType: Headers.formUrlEncodedContentType),
          );
    final status = response.statusCode ?? 0;
    if (status >= 300 && status < 400 || status == 401 || status == 403) {
      throw const PostalException('查詢連線已失效，請重新查詢。');
    }
    if (status != 200) throw const PostalException('學校郵務系統暫時無法使用，稍後再試。');
    final body = response.data ?? '';
    if (body.length > 4000000) throw const PostalException('查詢結果過大');
    return body;
  }

  Future<PostalPage> search(PostalQuery query) async {
    final q = query.normalized;
    if (!q.canSearch) throw const PostalException('請填寫收件人、手機號碼或郵件號碼其中一項。');
    final form = PostalHtml.form(await _request());
    return PostalHtml.page(await _request(PostalHtml.searchForm(form, q)), q);
  }

  Future<PostalPage> nextPage(PostalPage page) async {
    final form = page.nextForm;
    if (form == null) throw const PostalException('沒有更多結果');
    final next = PostalHtml.page(await _request(form), page.query);
    if (next.pageIndex != page.pageIndex + 1) {
      throw const PostalException('查詢結果格式已變更');
    }
    return next;
  }

  void close() => dio.close(force: true);
}
