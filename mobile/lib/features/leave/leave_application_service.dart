import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../../core/session/campus_session.dart';
import '../../core/session/session_coordinator.dart';
import 'leave_application_data.dart';
import 'leave_application_scripts.dart';
import 'leave_repository.dart';

abstract class LeaveApplicationGateway {
  Future<LeaveApplicationData> initialize();
  Future<LeaveApplicationData> agree(LeaveApplicationData data);
  Future<LeaveApplicationData> changeType(
    LeaveApplicationData data,
    String value,
  );
  Future<LeaveApplicationData> changeDates(
    LeaveApplicationData data,
    DateTime start,
    DateTime end,
  );
  Future<List<LeavePeriodChoice>> periods(LeaveApplicationData data);
  Future<LeaveApplicationData> selectPeriods(
    LeaveApplicationData data,
    List<String> values,
  );
  Future<void> cancelPeriods();
  Future<LeaveApplicationData> draft(
    LeaveApplicationData data,
    String reason,
    bool later,
  );
  Future<LeaveApplicationData> attach(
    LeaveApplicationData data,
    String name,
    Uint8List bytes,
  );
  Future<LeaveSubmitResult> submit(LeaveApplicationData data);
  void dispose();
}

typedef LeavePageEval = Future<dynamic> Function(String script);

/// One visible-or-covered school WebView owns the form for its entire lifetime.
/// School mutations are sent once; read polling never retries a submit/upload.
class SchoolLeaveApplication implements LeaveApplicationGateway {
  SchoolLeaveApplication({
    required this.session,
    required this.evaluate,
    required this.isActive,
    this.timeout = const Duration(seconds: 30),
    this.interval = const Duration(milliseconds: 400),
  }) : epoch = session.coordinator.epoch,
       owner = session.account ?? '',
       run = List.generate(
         16,
         (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
       ).join();

  final CampusSession session;
  final LeavePageEval evaluate;
  final bool Function() isActive;
  final int epoch;
  final String owner, run;
  final Duration timeout, interval;
  bool _busy = false, _disposed = false, _submitted = false;
  String? _pickerRevision;

  void guard() {
    session.coordinator.requireCurrent(epoch);
    if (_disposed || owner.isEmpty || session.account != owner) {
      throw SessionChanged();
    }
    if (!isActive()) {
      throw const LeaveApplicationException('操作已暫停，返回 App 後請重新確認');
    }
  }

  Future<T> serial<T>(Future<T> Function() action) async {
    guard();
    if (_busy) throw const LeaveApplicationException('正在更新校方表單，請稍候');
    _busy = true;
    try {
      return await action();
    } finally {
      _busy = false;
    }
  }

  Future<Map<String, dynamic>?> call(
    String op, [
    Map<String, dynamic> args = const {},
  ]) async {
    guard();
    final raw = await evaluate(
      leaveApplicationScript(run, op, {...args, 'owner': owner}),
    ).timeout(timeout);
    guard();
    if (raw == null || raw == 'null') return null;
    if (raw is! String) {
      throw const LeaveApplicationException('校方回應格式不同，請查看學校網頁');
    }
    final value = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    if (value['error'] case final String message) {
      throw LeaveApplicationException(message);
    }
    return value;
  }

  Future<Map<String, dynamic>> wait(
    String op, [
    Map<String, dynamic> args = const {},
  ]) async {
    final clock = Stopwatch()..start();
    while (clock.elapsed < timeout) {
      final value = await call(op, args);
      if (value != null) return value;
      await Future<void>.delayed(interval);
    }
    throw const LeaveApplicationException('校方回應逾時，請查看學校網頁；不會自動重送');
  }

  Map<String, dynamic> args(LeaveApplicationData data) => {
    'revision': data.revision,
  };

  @override
  Future<LeaveApplicationData> initialize() => serial(() async {
    final clock = Stopwatch()..start();
    while (clock.elapsed < timeout) {
      guard();
      dynamic navigation;
      try {
        navigation = await evaluate(leaveMenuNavigation(true)).timeout(timeout);
      } on TimeoutException {
        rethrow;
      } catch (_) {
        // Initial GUID redirects can replace the JavaScript context. Retry
        // discovery only, never a form update/upload/submission.
        guard();
        await Future<void>.delayed(interval);
        continue;
      }
      guard();
      if (navigation == 'session-expired') {
        throw const LeaveApplicationException('校務登入已過期，請重新登入');
      }
      if (navigation == 'ready' || navigation == 'interaction-required') {
        final value = await call('read');
        if (value != null) return LeaveApplicationData.fromJson(value);
      }
      await Future<void>.delayed(interval);
    }
    throw const LeaveApplicationException('無法開啟請假表單，請查看學校網頁');
  });

  Future<LeaveApplicationData> mutate(
    LeaveApplicationData data,
    String op,
    Map<String, dynamic> fields,
  ) async {
    if (_submitted) throw const LeaveApplicationException('已嘗試送出，請先查詢紀錄');
    final receipt = await call(op, {...args(data), ...fields});
    if (receipt == null) {
      throw const LeaveApplicationException('尚未確認校方是否收到操作，請查看學校網頁');
    }
    final value = await wait('settled', {'receipt': receipt['id'], 'kind': op});
    return LeaveApplicationData.fromJson(value);
  }

  @override
  Future<LeaveApplicationData> agree(LeaveApplicationData data) =>
      serial(() => mutate(data, 'agree', {}));
  @override
  Future<LeaveApplicationData> changeType(
    LeaveApplicationData data,
    String value,
  ) => serial(() async {
    if (!data.choices.any((c) => c.value == value && c.personal)) {
      throw const LeaveApplicationException('不支援此假別');
    }
    return mutate(data, 'type', {'value': value});
  });

  @override
  Future<LeaveApplicationData> changeDates(
    LeaveApplicationData data,
    DateTime start,
    DateTime end,
  ) => serial(() async {
    if (end.isBefore(start) || start.year < 2011 || end.year > 2910) {
      throw const LeaveApplicationException('請確認起訖日期');
    }
    // The first postback can clear/recalculate fields. Never send the old
    // revision alongside the second field or overlap the two updates.
    final first = await mutate(data, 'date', {
      'field': 'M_HOLIDAY_DATE_S',
      'value': schoolLeaveDate(start),
    });
    return mutate(first, 'date', {
      'field': 'M_HOLIDAY_DATE_E',
      'value': schoolLeaveDate(end),
    });
  });

  @override
  Future<List<LeavePeriodChoice>> periods(LeaveApplicationData data) =>
      serial(() async {
        await call('openPeriods', args(data));
        final value = await wait('periods');
        _pickerRevision = value['revision'] as String;
        return [
          for (final row in (value['periods'] as List).cast<Map>())
            LeavePeriodChoice(
              value: row['value'] as String,
              date: row['date'] as String,
              period: row['period'] as String,
              course: row['course'] as String,
              selected: row['selected'] == true,
            ),
        ];
      });

  @override
  Future<LeaveApplicationData> selectPeriods(
    LeaveApplicationData data,
    List<String> values,
  ) => serial(() async {
    if (_pickerRevision == null || values.isEmpty) {
      throw const LeaveApplicationException('請選擇節次');
    }
    return mutate(data, 'applyPeriods', {
      'pickerRevision': _pickerRevision,
      'values': values,
    });
  });
  @override
  Future<void> cancelPeriods() => serial(() async {
    await call('cancelPeriods');
    _pickerRevision = null;
  });

  @override
  Future<LeaveApplicationData> draft(
    LeaveApplicationData data,
    String reason,
    bool later,
  ) => serial(() async {
    final value = await call('draft', {
      ...args(data),
      'reason': reason,
      'later': later,
    });
    if (value == null) throw const LeaveApplicationException('請重新確認校方表單');
    return LeaveApplicationData.fromJson(value);
  });

  /// A transport safety cap, not a statement of the school's file-size policy.
  static const attachmentLimit = 10 * 1024 * 1024;
  @override
  Future<LeaveApplicationData> attach(
    LeaveApplicationData data,
    String name,
    Uint8List bytes,
  ) => serial(() async {
    if (bytes.isEmpty ||
        bytes.length > attachmentLimit ||
        name.contains(RegExp(r'[/\\\x00]'))) {
      throw const LeaveApplicationException('請選擇 10 MB 以下的非空白檔案');
    }
    final extension = name.split('.').last.toLowerCase();
    if (!data.extensions.contains(extension)) {
      throw const LeaveApplicationException('校方不支援此附件格式');
    }
    final start = await call('uploadStart', {...args(data), 'name': name});
    if (start == null) throw const LeaveApplicationException('無法準備附件');
    // Multiples of three keep separately encoded chunks concatenable.
    for (var i = 0; i < bytes.length; i += 49152) {
      final end = min(i + 49152, bytes.length);
      await call('uploadChunk', {
        'id': start['id'],
        'chunk': base64Encode(bytes.sublist(i, end)),
      });
    }
    await call('uploadSend', {...args(data), 'id': start['id']});
    return LeaveApplicationData.fromJson(
      await wait('uploadResult', args(data)),
    );
  });

  @override
  Future<LeaveSubmitResult> submit(
    LeaveApplicationData data,
  ) => serial(() async {
    final invalid = data.validate(data.reason);
    if (invalid != null) throw LeaveApplicationException(invalid);
    if (_submitted) throw const LeaveApplicationException('已嘗試送出，請先查詢紀錄');
    // Lock before the bridge call: navigation/timeout can swallow the reply even
    // when the server received the request. Never offer automatic resend.
    _submitted = true;
    try {
      await call('submit', {
        ...args(data),
        'expected': {
          'type': data.type,
          'start': data.start,
          'end': data.end,
          'reason': data.reason,
          'later': data.later,
          'periods': data.periods,
        },
      });
      final result = await wait('submissionResult');
      return LeaveSubmitResult(
        applicationId: result['applicationId'] as String,
        message: result['message'] as String,
      );
    } on SessionChanged {
      rethrow;
    } catch (_) {
      return const LeaveSubmitResult(message: '尚未確認送出結果。請先查詢請假紀錄，勿重複申請。');
    }
  });

  @override
  void dispose() {
    _disposed = true;
  }
}
