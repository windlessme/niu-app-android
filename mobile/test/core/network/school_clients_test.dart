import 'dart:typed_data';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/core/network/school_clients.dart';

class FixtureAdapter implements HttpClientAdapter {
  FixtureAdapter(this.body);
  final String body;
  RequestOptions? request;
  String sentBody = '';

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    request = options;
    if (requestStream != null) {
      final bytes = await requestStream.expand((chunk) => chunk).toList();
      sentBody = utf8.decode(bytes);
    }
    return ResponseBody.fromString(
      body,
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('API clients reject untrusted origins and mixed service clients', () {
    expect(() => schoolClient('https://attacker.example'), throwsArgumentError);
    final moodle = schoolClient('https://euni.niu.edu.tw');
    expect(() => SsoApiClient(moodle), throwsArgumentError);
    moodle.close();
  });

  test('Moodle credentials use POST body and never URI query', () async {
    final http = schoolClient('https://euni.niu.edu.tw');
    final adapter = FixtureAdapter('{"token":"fixture-token"}');
    http.httpClientAdapter = adapter;
    final client = MoodleApiClient(http);
    expect(await client.authenticate('fixture', 'a+b&c'), 'fixture-token');
    expect(adapter.request!.method, 'POST');
    expect(adapter.request!.uri.query, isEmpty);
    expect(adapter.sentBody, contains('a%2Bb%26c'));
    http.close();
  });

  test('Moodle HTTP 200 error payload is not treated as success', () async {
    final http = schoolClient('https://euni.niu.edu.tw');
    http.httpClientAdapter = FixtureAdapter(
      '{"exception":"invalid_token","errorcode":"invalidtoken"}',
    );
    await expectLater(
      MoodleApiClient(
        http,
      ).read('fixture', 'core_webservice_get_site_info', {}),
      throwsA(isA<SchoolApiException>()),
    );
    http.close();
  });

  test('SSO identity must match the requested account', () async {
    final http = schoolClient('https://ccsys1.niu.edu.tw');
    http.httpClientAdapter = FixtureAdapter(
      '{"data":{"acnt":"other-account"}}',
    );
    await expectLater(
      SsoApiClient(http).verifyIdentity('fixture', 'expected'),
      throwsA(isA<SchoolApiException>()),
    );
    http.close();
  });
}
