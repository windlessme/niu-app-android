import 'dart:convert';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/core/analytics/usage_heartbeat.dart';
import 'package:niu_mobile/core/session/campus_session.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fakes.dart';

/// Records what would be sent; nothing reaches the real endpoint.
class _Server {
  final bodies = <Map<String, dynamic>>[];
  int status = 204;
  Future<int?> post(String body) async {
    bodies.add(jsonDecode(body) as Map<String, dynamic>);
    return status;
  }
}

final _v4 = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

/// Lets an unawaited report finish its SharedPreferences and fake POST.
Future<void> settle(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pump();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('once per Taipei day, with the same random id', () async {
    final server = _Server();
    // 2026-10-09 15:59 UTC is 23:59 in Taipei.
    var now = DateTime.utc(2026, 10, 9, 15, 59);
    final heartbeat = UsageHeartbeat(
      post: server.post,
      version: () async => '1.2.0',
      clock: () => now,
    );
    await heartbeat.report();
    await heartbeat.report();
    expect(server.bodies, hasLength(1));
    final body = server.bodies.single;
    expect(body.keys, ['installation_id', 'platform', 'app_version']);
    expect(body['platform'], 'android');
    expect(body['app_version'], '1.2.0');
    expect(body['installation_id'], matches(_v4));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(UsageHeartbeat.dayKey), '2026-10-09');

    now = DateTime.utc(2026, 10, 9, 16, 1); // 00:01 the next Taipei day
    await heartbeat.report();
    expect(server.bodies, hasLength(2));
    expect(server.bodies.last['installation_id'], body['installation_id']);
  });

  test('only a 204 counts; failures retry on the next call', () async {
    final server = _Server()..status = 503;
    final heartbeat = UsageHeartbeat(
      post: server.post,
      version: () async => '1.2.0',
    );
    await heartbeat.report();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(UsageHeartbeat.dayKey), isNull);
    // Offline or timed out: silent.
    final offline = UsageHeartbeat(
      post: (_) => throw StateError('offline'),
      version: () async => '1.2.0',
    );
    await offline.report();
    server.status = 204;
    await heartbeat.report();
    expect(server.bodies, hasLength(2));
    expect(prefs.getString(UsageHeartbeat.dayKey), isNotNull);
  });

  test('one request at a time', () async {
    final server = _Server();
    final heartbeat = UsageHeartbeat(
      post: server.post,
      version: () async => '1.2.0',
    );
    await Future.wait([heartbeat.report(), heartbeat.report()]);
    expect(server.bodies, hasLength(1));
  });

  test('versions outside the server format are left out', () async {
    expect(UsageHeartbeat.reportableVersion('1.2.0'), '1.2.0');
    expect(UsageHeartbeat.reportableVersion('10.12'), '10.12');
    expect(UsageHeartbeat.reportableVersion('1.0.0-debug'), isNull);
    expect(UsageHeartbeat.reportableVersion('1.2.3.4'), isNull);
    expect(UsageHeartbeat.reportableVersion(null), isNull);
    final server = _Server();
    await UsageHeartbeat(
      post: server.post,
      version: () async => '1.0.0-debug',
    ).report();
    expect(server.bodies.single.containsKey('app_version'), isFalse);
  });

  test('an invalid saved id is replaced; a valid one is kept', () async {
    SharedPreferences.setMockInitialValues({
      UsageHeartbeat.idKey: 'not-a-uuid',
    });
    final server = _Server();
    await UsageHeartbeat(post: server.post, version: () async => null).report();
    final id = server.bodies.single['installation_id'] as String;
    expect(id, matches(_v4));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(UsageHeartbeat.idKey), id);
    for (var i = 0; i < 50; i++) {
      expect(UsageHeartbeat.uuidV4(Random(i)), matches(_v4));
    }
  });

  testWidgets('reports for a signed-in school account, not the demo', (
    tester,
  ) async {
    final server = _Server();
    var now = DateTime.utc(2026, 10, 9, 4);
    final heartbeat = UsageHeartbeat(
      post: server.post,
      version: () async => '1.2.0',
      clock: () => now,
    );
    final session = CampusSession(
      vault: MemoryVault(),
      sso: FreshSso(),
      platformCleanup: [],
    );
    addTearDown(session.dispose);
    final trigger = UsageHeartbeatTrigger(
      session,
      heartbeat: heartbeat,
      allowed: () => true,
      clock: () => now,
    )..start();

    // Signed out, or in the review demo: nothing is sent.
    await settle(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.runAsync(() => session.enterDemo());
    await settle(tester);
    expect(server.bodies, isEmpty);
    await tester.runAsync(() => session.logout());

    // Signing in reports once; the id survives signing out and in again.
    await tester.runAsync(() => session.acceptToken('fixture', 'b123'));
    await settle(tester);
    expect(server.bodies, hasLength(1));
    final id = server.bodies.single['installation_id'];
    await tester.runAsync(() => session.logout());
    now = now.add(const Duration(days: 1));
    await tester.runAsync(() => session.acceptToken('fixture', 'b123'));
    await settle(tester);
    expect(server.bodies, hasLength(2));
    expect(server.bodies.last['installation_id'], id);

    // A return to the app on a new day reports again.
    now = now.add(const Duration(days: 1));
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await settle(tester);
    expect(server.bodies, hasLength(3));
    trigger.dispose(); // Cancels the midnight timer before the test ends.
  });
}
