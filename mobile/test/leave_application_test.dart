import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/core/session/campus_session.dart';
import 'package:niu_mobile/core/session/session_coordinator.dart';
import 'package:niu_mobile/features/leave/leave_application_data.dart';
import 'package:niu_mobile/features/leave/leave_application_scripts.dart';
import 'package:niu_mobile/features/leave/leave_application_service.dart';

import 'features/authentication_session_test.dart' show MemoryVault;

Map<String, dynamic> applicationFixture({String revision = 'd:1'}) => {
  'revision': revision,
  'choices': [
    {'value': '023', 'label': '事假'},
    {'value': '003', 'label': '公假'},
    {'value': 'school', 'label': '學校公假'},
    {'value': '002', 'label': '病假'},
  ],
  'type': '023',
  'start': '115/10/01',
  'end': '115/10/01',
  'reason': '測試事由',
  'reasonLimit': 1000,
  'later': false,
  'canDeferAttachment': true,
  'periods': [
    ['115/10/01', '第一節'],
  ],
  'total': '1',
  'attachments': [],
  'extensions': ['pdf', 'png'],
};

class ScriptWire {
  final calls = <(String, Map<String, dynamic>)>[];
  FutureOr<Object?> Function(String, Map<String, dynamic>)? reply;
  Future<Object?> evaluate(String source) async {
    final match = RegExp(
      r'const run=(.*), op=(.*), args=(.*);',
    ).firstMatch(source);
    if (match == null) return 'ready';
    final op = jsonDecode(match[2]!) as String;
    final args = jsonDecode(match[3]!) as Map<String, dynamic>;
    calls.add((op, args));
    final value = await reply?.call(op, args);
    return value == null ? null : jsonEncode(value);
  }
}

void main() {
  test('school date conversion rejects rollover and preserves civil dates', () {
    expect(parseSchoolLeaveDate('115/10/01'), DateTime(2026, 10, 1));
    expect(parseSchoolLeaveDate('2026/10/01'), DateTime(2026, 10, 1));
    expect(parseSchoolLeaveDate('115/02/30'), isNull);
    expect(schoolLeaveDate(DateTime(2026, 10, 1)), '115/10/01');
  });
  test(
    'form retains unknown totals, excludes public leave and validates before submit',
    () {
      final data = LeaveApplicationData.fromJson({
        ...applicationFixture(),
        'total': null,
      });
      expect(data.choices.map((c) => c.label), ['事假', '病假']);
      expect(data.total, isNull);
      expect(data.validate(''), isNotNull);
      expect(data.validate('原因'), isNull);
      expect(
        LeaveApplicationData.fromJson({
          ...applicationFixture(),
          'periods': [],
        }).validate('原因'),
        isNotNull,
      );
    },
  );

  late CampusSession session;
  late SchoolLeaveApplication gateway;
  late ScriptWire wire;
  late bool active;
  setUp(() {
    active = true;
    session = CampusSession(vault: MemoryVault(), platformCleanup: [])
      ..account = 'b123';
    wire = ScriptWire();
    gateway = SchoolLeaveApplication(
      session: session,
      evaluate: wire.evaluate,
      isActive: () => active,
      timeout: const Duration(milliseconds: 100),
      interval: const Duration(milliseconds: 1),
    );
  });
  tearDown(() {
    gateway.dispose();
    session.dispose();
  });

  test('dates postback sequentially with the returned form revision', () async {
    wire.reply = (op, args) => switch (op) {
      'date' => {'id': 'receipt'},
      'settled' => applicationFixture(revision: 'd:2'),
      _ => null,
    };
    await gateway.changeDates(
      LeaveApplicationData.fromJson(applicationFixture()),
      DateTime(2026, 10, 1),
      DateTime(2026, 10, 2),
    );
    expect(wire.calls.map((c) => c.$1), ['date', 'settled', 'date', 'settled']);
    expect(wire.calls[2].$2['revision'], 'd:2');
    expect(wire.calls[2].$2['value'], '115/10/02');
  });
  test('no overlapping updates and no work while inactive', () async {
    final pending = Completer<Object?>();
    wire.reply = (op, _) =>
        op == 'type' ? pending.future : applicationFixture();
    final first = gateway.changeType(
      LeaveApplicationData.fromJson(applicationFixture()),
      '002',
    );
    await expectLater(
      gateway.changeType(
        LeaveApplicationData.fromJson(applicationFixture()),
        '023',
      ),
      throwsA(isA<LeaveApplicationException>()),
    );
    pending.complete({'id': 'r'});
    await first;
    final count = wire.calls.length;
    active = false;
    await expectLater(
      gateway.initialize(),
      throwsA(isA<LeaveApplicationException>()),
    );
    expect(wire.calls.length, count);
  });
  test('logout during update rejects its late response', () async {
    final pending = Completer<Object?>();
    wire.reply = (_, _) => pending.future;
    final first = gateway.changeType(
      LeaveApplicationData.fromJson(applicationFixture()),
      '002',
    );
    final assertion = expectLater(first, throwsA(isA<SessionChanged>()));
    await session.logout();
    pending.complete({'id': 'r'});
    await assertion;
    expect(wire.calls.map((c) => c.$1), ['type']);
  });
  test('submission timeout is unknown and never resubmitted', () async {
    wire.reply = (op, _) => op == 'submit' ? {'ok': true} : null;
    final data = LeaveApplicationData.fromJson(applicationFixture());
    final result = await gateway.submit(data);
    expect(result.confirmed, isFalse);
    await expectLater(
      gateway.submit(data),
      throwsA(isA<LeaveApplicationException>()),
    );
    expect(wire.calls.where((c) => c.$1 == 'submit'), hasLength(1));
  });
  test('only confirmed server number yields a success result', () async {
    wire.reply = (op, _) => op == 'submissionResult'
        ? {'applicationId': 'fixture-001', 'message': '已建立假單'}
        : {'ok': true};
    final result = await gateway.submit(
      LeaveApplicationData.fromJson(applicationFixture()),
    );
    expect(result.confirmed, isTrue);
    expect(result.applicationId, 'fixture-001');
  });
  test(
    'public leave and unsupported attachments never invoke school mutations',
    () async {
      await expectLater(
        gateway.changeType(
          LeaveApplicationData.fromJson(applicationFixture()),
          '003',
        ),
        throwsA(isA<LeaveApplicationException>()),
      );
      await expectLater(
        gateway.attach(
          LeaveApplicationData.fromJson(applicationFixture()),
          'file.exe',
          Uint8List.fromList([1]),
        ),
        throwsA(isA<LeaveApplicationException>()),
      );
      expect(wire.calls, isEmpty);
    },
  );
  test(
    'upload chunks reconstruct bytes; attach is sent once and not submission',
    () async {
      wire.reply = (op, _) => switch (op) {
        'uploadStart' => {'id': 'u'},
        'uploadResult' => applicationFixture(),
        _ => {'ok': true},
      };
      final bytes = Uint8List.fromList(List.generate(110000, (i) => i % 256));
      await gateway.attach(
        LeaveApplicationData.fromJson(applicationFixture()),
        '證明.pdf',
        bytes,
      );
      final encoded = wire.calls
          .where((c) => c.$1 == 'uploadChunk')
          .map((c) => c.$2['chunk'])
          .join();
      expect(base64Decode(encoded), bytes);
      expect(wire.calls.where((c) => c.$1 == 'uploadSend'), hasLength(1));
      expect(wire.calls.where((c) => c.$1 == 'submit'), isEmpty);
    },
  );
  test('browser scripts guard identity, public leave and duplicate submit', () {
    final result = Process.runSync('node', [
      'test/leave_application_dom.cjs',
      leaveApplicationRuntime,
    ]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  });
}
