import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/core/session/session_coordinator.dart';

void main() {
  test('concurrent logout shares cleanup and blocks new login', () async {
    final coordinator = SessionCoordinator();
    final gate = Completer<void>();
    var calls = 0;
    Future<void> clear() async {
      calls++;
      await gate.future;
    }

    final first = coordinator.logout(clear);
    final second = coordinator.logout(clear);
    expect(identical(first, second), isTrue);
    await expectLater(
      coordinator.authenticate(CampusService.sso, (_) async {}),
      throwsA(isA<SessionChanged>()),
    );
    gate.complete();
    await first;
    expect(calls, 1);
  });

  test('concurrent refresh uses one authentication operation', () async {
    final coordinator = SessionCoordinator();
    final gate = Completer<void>();
    var calls = 0;
    Future<void> action(int _) async {
      calls++;
      await gate.future;
    }

    final first = coordinator.authenticate(CampusService.sso, action);
    final second = coordinator.authenticate(CampusService.sso, action);
    expect(identical(first, second), isTrue);
    gate.complete();
    await Future.wait([first, second]);
    expect(calls, 1);
    expect(coordinator.status(CampusService.sso), ServiceStatus.valid);
  });

  test('late authentication cannot restore a logged-out session', () async {
    final coordinator = SessionCoordinator();
    final gate = Completer<void>();
    final task = coordinator.authenticate(
      CampusService.sso,
      (_) => gate.future,
    );
    final rejected = expectLater(task, throwsA(isA<SessionChanged>()));
    await coordinator.logout(() async {});
    gate.complete();
    await rejected;
    expect(coordinator.status(CampusService.sso), ServiceStatus.unknown);
  });

  test('failed cleanup blocks new authentication until recovery', () async {
    final coordinator = SessionCoordinator();
    await expectLater(
      coordinator.logout(() async => throw StateError('disk')),
      throwsStateError,
    );
    await expectLater(
      coordinator.authenticate(CampusService.sso, (_) async {}),
      throwsA(isA<SessionChanged>()),
    );
    await coordinator.retryCleanup(() async {});
    await coordinator.authenticate(CampusService.sso, (_) async {});
    expect(coordinator.status(CampusService.sso), ServiceStatus.valid);
  });

  test('old completion cannot remove a new single-flight operation', () async {
    final coordinator = SessionCoordinator();
    final oldGate = Completer<void>();
    final newGate = Completer<void>();
    final started = Completer<void>();
    final old = coordinator.authenticate(CampusService.sso, (_) {
      started.complete();
      return oldGate.future;
    });
    final rejected = expectLater(old, throwsA(isA<SessionChanged>()));
    await started.future;
    await coordinator.logout(() async {});
    final current = coordinator.authenticate(
      CampusService.sso,
      (_) => newGate.future,
    );
    oldGate.complete();
    await rejected;
    final joined = coordinator.authenticate(CampusService.sso, (_) async {
      fail('New session authentication should be shared');
    });
    expect(identical(current, joined), isTrue);
    newGate.complete();
    await current;
  });
}
