import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';

import '../../core/demo/demo_data.dart';
import '../../core/demo/demo_documents.dart';
import '../../core/network/school_clients.dart';
import 'moodle_repository.dart';

/// A well-formed attendance link; the demo result screen never opens it.
const demoAttendanceLink =
    'https://euni.niu.edu.tw/mod/attendance/attendance.php?qrpass=DEMO&sessid=1';

class DemoMoodleApiClient extends MoodleApiClient {
  DemoMoodleApiClient()
    : super(Dio(BaseOptions(baseUrl: 'https://euni.niu.edu.tw')));

  @override
  Future<Object?> read(
    String token,
    String function,
    Map<String, Object> params,
  ) async => jsonDecode(jsonEncode(DemoData.moodle(function, params)));

  @override
  Future<Object?> mutate(
    String token,
    String function,
    Map<String, Object> params,
  ) async => switch (function) {
    'core_files_get_unused_draft_itemid' => {'itemid': 1},
    'tool_mobile_get_autologin_key' => throw const FormatException(
      '示範模式不開啟 M 園區網頁',
    ),
    _ => <Object?>[],
  };

  @override
  Future<Object?> upload(
    String token,
    int itemId,
    String filename,
    List<int> bytes,
  ) async => [
    {'itemid': itemId},
  ];
}

class DemoMoodleRepository extends MoodleRepository {
  DemoMoodleRepository()
    : super(
        DemoMoodleApiClient(),
        const MoodleSession(account: 'niulifedemo', token: 'demo', userId: 1),
      );

  @override
  Future<Uint8List> download(String raw) async {
    final name = Uri.tryParse(raw)?.pathSegments.lastOrNull ?? 'file.pdf';
    return demoPdf(name);
  }

  @override
  Future<Uri> webUri(Uri target) async =>
      throw const FormatException('示範模式不開啟 M 園區網頁');
}
