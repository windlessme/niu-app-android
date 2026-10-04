/// Fakes shared by several test files.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:niu_mobile/core/network/school_clients.dart';
import 'package:niu_mobile/core/platform/schedule_gateway.dart';
import 'package:niu_mobile/core/session/campus_session.dart';
import 'package:niu_mobile/core/storage/credential_vault.dart';

class MemoryVault implements CredentialVault {
  final values = <String, String>{};
  Completer<void>? gate;
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    if (gate != null) await gate!.future;
    values[key] = value;
  }

  @override
  Future<void> clear() async => values.clear();
}

class FixtureSso extends SsoApiClient {
  FixtureSso() : super(schoolClient('https://ccsys1.niu.edu.tw'));
  final result = Completer<Map<String, dynamic>>();
  final requested = Completer<void>();
  @override
  Future<Map<String, dynamic>> verifyIdentity(
    String token,
    String account,
  ) async {
    if (!requested.isCompleted) requested.complete();
    return await result.future;
  }
}

class FreshSso extends SsoApiClient {
  FreshSso() : super(schoolClient('https://ccsys1.niu.edu.tw'));
  int verifications = 0;
  @override
  Future<Map<String, dynamic>> verifyIdentity(
    String token,
    String account,
  ) async {
    verifications++;
    return {'acnt': account, 'chName': '測試'};
  }

  @override
  Future<Uri> academicEntry(String token, String account) async =>
      Uri.parse('https://acade.niu.edu.tw/NIU/Login.aspx?GUID=fixture');
}

class WireAdapter implements HttpClientAdapter {
  WireAdapter(this.reply);
  final Object? Function(RequestOptions request) reply;
  final requests = <RequestOptions>[];
  final bodies = <RequestOptions, String>{};
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (requestStream != null) {
      final bytes = await requestStream.expand((chunk) => chunk).toList();
      bodies[options] = utf8.decode(bytes, allowMalformed: true);
      options.extra['wireBody'] = bodies[options];
    }
    final result = reply(options);
    if (result is Exception) throw result;
    return ResponseBody.fromString(
      jsonEncode(result),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class SignedSession extends CampusSession {
  SignedSession(CredentialVault vault) : super(vault: vault);
  @override
  bool get isSignedIn => account != null;
}

class ScheduleSession extends CampusSession {
  ScheduleSession(MemoryVault vault) : super(vault: vault, platformCleanup: []);
  int portalRequests = 0;

  @override
  bool get isSignedIn => account != null && !isOffline;

  @override
  Future<Uri> academicEntry() async {
    portalRequests++;
    return Uri.parse('https://acade.niu.edu.tw/NIU/MainFrame.aspx');
  }
}

class FakeGateway extends ScheduleGateway {
  final sent = <String, List<CampusNotice>>{};
  @override
  Future<void> setNotifications(String kind, List<CampusNotice> items) async =>
      sent[kind] = items;
  @override
  Future<ReminderStatus> reminderStatus() async =>
      const ReminderStatus(enabled: false, permitted: true);
  bool? classNow;
  bool permitted = true;
  @override
  Future<bool> setClassNow({required bool enabled}) async {
    classNow = enabled;
    return !enabled || permitted;
  }
}
