import 'dart:typed_data';

import 'package:flutter/services.dart';

import '../../core/demo/demo_account.dart';
import '../../core/demo/demo_data.dart';
import 'leave_application_data.dart';
import 'leave_application_service.dart';

/// Simulates the school form; nothing is submitted.
class DemoLeaveGateway implements LeaveApplicationGateway {
  var _revision = 0;
  var _form = <String, dynamic>{
    'choices': [
      {'value': '023', 'label': '事假'},
      {'value': '002', 'label': '病假'},
      {'value': '005', 'label': '生理假'},
      {'value': '009', 'label': '心理健康假'},
    ],
    'type': '023',
    'start': DemoData.rocDate(1),
    'end': DemoData.rocDate(1),
    // adb cannot type Chinese; screenshots start with a typical reason.
    'reason': storeScreenshots ? '家中有事需返鄉處理' : '',
    'reasonLimit': 1000,
    'later': false,
    'canDeferAttachment': true,
    'periods': <List<String>>[],
    'total': null,
    'attachments': <String>[],
    'extensions': ['pdf', 'jpg', 'jpeg', 'png'],
  };

  Future<LeaveApplicationData> _next([Map<String, dynamic>? change]) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    _form = {..._form, ...?change};
    return LeaveApplicationData.fromJson({
      ..._form,
      'revision': 'demo:${++_revision}',
    });
  }

  @override
  Future<LeaveApplicationData> initialize() async => storeScreenshots
      // The first form carries the reason the screen fills in once.
      ? _next()
      : const LeaveApplicationData(revision: 'demo:0', notice: '請假注意事項');

  @override
  Future<LeaveApplicationData> agree(LeaveApplicationData data) => _next();

  @override
  Future<LeaveApplicationData> changeType(
    LeaveApplicationData data,
    String value,
  ) => _next({'type': value});

  @override
  Future<LeaveApplicationData> changeDates(
    LeaveApplicationData data,
    DateTime start,
    DateTime end,
  ) => _next({
    'start': schoolLeaveDate(start),
    'end': schoolLeaveDate(end),
    'periods': <List<String>>[],
    'total': null,
  });

  @override
  Future<List<LeavePeriodChoice>> periods(LeaveApplicationData data) async {
    final from = parseSchoolLeaveDate(data.start);
    final to = parseSchoolLeaveDate(data.end);
    if (from == null || to == null) return const [];
    final rows = DemoData.scheduleRows;
    final chosen = {for (final row in data.periods) row.join('|')};
    final result = <LeavePeriodChoice>[];
    for (
      var day = from;
      !day.isAfter(to) && result.length < 60;
      day = day.add(const Duration(days: 1))
    ) {
      final column = day.weekday + 1; // 星期一 is column 2.
      if (day.weekday > 5) continue;
      for (final row in rows.skip(1)) {
        final cell = row[column].split('\n');
        if (cell.length < 2) continue;
        final date = schoolLeaveDate(day);
        final period = '第${row[0]}節';
        result.add(
          LeavePeriodChoice(
            value: '$date|$period|${cell[1]}',
            date: date,
            period: period,
            course: cell[1],
            selected: chosen.contains('$date|$period|${cell[1]}'),
          ),
        );
      }
    }
    return result;
  }

  @override
  Future<LeaveApplicationData> selectPeriods(
    LeaveApplicationData data,
    List<String> values,
  ) => _next({
    'periods': [for (final v in values) v.split('|')],
    'total': values.isEmpty ? null : '${values.length}',
  });

  @override
  Future<void> cancelPeriods() async {}

  @override
  Future<LeaveApplicationData> draft(
    LeaveApplicationData data,
    String reason,
    bool later,
  ) => _next({'reason': reason, 'later': later});

  @override
  Future<LeaveApplicationData> attach(
    LeaveApplicationData data,
    String name,
    Uint8List bytes,
  ) => _next({
    'attachments': [
      ...(_form['attachments'] as List).cast<String>(),
      name.replaceAll(RegExp(r'\.[^.]*$'), ''),
    ],
  });

  @override
  Future<LeaveSubmitResult> submit(LeaveApplicationData data) async {
    await Future<void>.delayed(const Duration(milliseconds: 800));
    return LeaveSubmitResult(
      applicationId: storeScreenshots ? 'D1151002' : 'DEMO-0001',
      message: storeScreenshots
          ? '學校已收到你的請假申請，審核結果可在請假紀錄查看。'
          : '示範模式：已模擬送出，沒有傳送到學校請假系統。',
    );
  }

  @override
  void dispose() {}
}
