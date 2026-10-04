import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/core/network/school_clients.dart';
import 'package:niu_mobile/features/moodle/moodle_repository.dart';
import 'package:niu_mobile/features/moodle/moodle_session_store.dart';
import 'package:niu_mobile/features/attendance/attendance_open_flow.dart';
import '../../support/fakes.dart';

class AttachmentAdapter implements HttpClientAdapter {
  String contentType = 'application/pdf';
  RequestOptions? request;
  Completer<void>? gate;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancel,
  ) async {
    request = options;
    if (gate != null) await gate!.future;
    return ResponseBody.fromBytes(
      [37, 80, 68, 70],
      200,
      headers: {
        'content-type': [contentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test(
    'attachment downloads bytes internally with redirects disabled',
    () async {
      final adapter = AttachmentAdapter();
      final repo = MoodleRepository(
        MoodleApiClient(
          schoolClient('https://euni.niu.edu.tw')..httpClientAdapter = adapter,
        ),
        const MoodleSession(account: 'b123', token: 'secret', userId: 7),
      );
      expect(
        await repo.download(
          'https://euni.niu.edu.tw/pluginfile.php/1/report.pdf',
        ),
        [37, 80, 68, 70],
      );
      expect(adapter.request!.followRedirects, false);
      expect(
        adapter.request!.uri.path,
        '/webservice/pluginfile.php/1/report.pdf',
      );
      expect(adapter.request!.uri.queryParameters['token'], 'secret');
      adapter.contentType = 'text/html';
      await expectLater(
        repo.download('https://euni.niu.edu.tw/pluginfile.php/1/report.pdf'),
        throwsFormatException,
      );
    },
  );
  test('logout during attachment download discards the response', () async {
    final adapter = AttachmentAdapter()..gate = Completer<void>();
    final repo = MoodleRepository(
      MoodleApiClient(
        schoolClient('https://euni.niu.edu.tw')..httpClientAdapter = adapter,
      ),
      const MoodleSession(account: 'b123', token: 'secret', userId: 7),
    );
    final request = repo.download(
      'https://euni.niu.edu.tw/pluginfile.php/1/report.pdf',
    );
    final assertion = expectLater(request, throwsStateError);
    await repo.invalidate();
    adapter.gate!.complete();
    await assertion;
  });
  const qr =
      'https://euni.niu.edu.tw/mod/attendance/attendance.php?qrpass=a&sessid=4';
  test(
    'QR confirmation cancel never navigates and overlapping scan is ignored',
    () async {
      final flow = AttendanceOpenFlow();
      final decision = Completer<bool>();
      var opened = 0, resumed = 0;
      Future<void> attempt() => flow.open(
        qr,
        pause: () async {},
        confirm: (_) => decision.future,
        navigate: (_) async {
          opened++;
        },
        resume: () async {
          resumed++;
        },
      );
      final pending = attempt();
      await attempt();
      decision.complete(false);
      await pending;
      expect(opened, 0);
      expect(resumed, 1);
      expect(flow.busy, false);
    },
  );
  test(
    'navigation failure releases QR single-flight lock and resumes camera',
    () async {
      final flow = AttendanceOpenFlow();
      var resumed = 0;
      await expectLater(
        flow.open(
          qr,
          pause: () async {},
          confirm: (_) async => true,
          navigate: (_) async => throw StateError('navigation'),
          resume: () async {
            resumed++;
          },
        ),
        throwsStateError,
      );
      expect(flow.busy, false);
      expect(resumed, 1);
    },
  );
  test(
    'encrypted envelope restores only matching account and verified user id',
    () async {
      final vault = MemoryVault();
      final owner = SignedSession(vault)..account = 'b123';
      final store = MoodleSessionStore(owner);
      await store.save(
        const MoodleSession(
          account: 'b123',
          token: 'secret',
          userId: 7,
          privateToken: 'private',
        ),
      );
      final adapter = WireAdapter((_) => {'userid': 7, 'username': 'b123'});
      final api = MoodleApiClient(
        schoolClient('https://euni.niu.edu.tw')..httpClientAdapter = adapter,
      );
      expect((await store.restore(api))!.session.privateToken, 'private');
      owner.account = 'other';
      expect(await store.restore(api), isNull);
      expect(adapter.requests.length, 1);
      await store.dispose();
    },
  );
  test(
    'cleanup waits for in-flight encrypted write and removes its result',
    () async {
      final vault = MemoryVault()..gate = Completer<void>();
      final owner = SignedSession(vault)..account = 'b123';
      final store = MoodleSessionStore(owner);
      final saving = store.save(
        const MoodleSession(account: 'b123', token: 'secret', userId: 7),
      );
      final savingCheck = expectLater(saving, throwsA(anything));
      final cleanup = owner.coordinator.logout(store.clear);
      vault.gate!.complete();
      await savingCheck;
      await cleanup;
      expect(vault.values['moodleSession'], '');
    },
  );
  test('restored token user-id mismatch rejected', () async {
    final vault = MemoryVault()
      ..values['moodleSession'] = jsonEncode({
        'account': 'b123',
        'token': 't',
        'userId': 7,
      });
    final store = MoodleSessionStore(SignedSession(vault)..account = 'b123');
    final api = MoodleApiClient(
      schoolClient('https://euni.niu.edu.tw')
        ..httpClientAdapter = WireAdapter(
          (_) => {'userid': 8, 'username': 'b123'},
        ),
    );
    await expectLater(store.restore(api), throwsStateError);
    await store.dispose();
  });
}
