import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';

import '../../core/demo/demo_data.dart';
import '../../core/network/school_clients.dart';
import '../events/event_actions.dart';
import '../events/events_screen.dart';
import '../leave/leave_application_data.dart';
import '../leave/leave_application_service.dart';
import '../library/library_repository.dart';
import '../moodle/moodle_repository.dart';
import '../postal/postal_models.dart';
import '../postal/postal_service.dart';

/// A one-page PDF saying it is sample content, for certificates and files.
Uint8List demoPdf(String title) {
  final text = title.replaceAll(RegExp(r'[^\x20-\x7e]'), '');
  final stream =
      'BT /F1 22 Tf 72 720 Td (NIU-Life demo) Tj 0 -36 Td /F1 14 Tf '
      '($text) Tj 0 -24 Td (Sample content. Not an official document.) Tj ET';
  final objects = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
        '/Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
    '<< /Length ${stream.length} >>\nstream\n$stream\nendstream',
  ];
  final out = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (final (i, body) in objects.indexed) {
    offsets.add(out.length);
    out.write('${i + 1} 0 obj\n$body\nendobj\n');
  }
  final xref = out.length;
  out.write('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n');
  for (final offset in offsets) {
    out.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  out.write(
    'trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n'
    'startxref\n$xref\n%%EOF\n',
  );
  return Uint8List.fromList(ascii.encode(out.toString()));
}

// ── 活動報名 ──────────────────────────────────────────────────────────────

/// Registrations made during the demo, kept in memory only.
abstract final class DemoEvents {
  static final registered = <String>{'11188'};

  static List<Map<String, dynamic>> list({required bool applied}) {
    final all = [DemoData.registeredEvent, ...DemoData.events];
    return [
      for (final event in all)
        if (applied == registered.contains(event['id']))
          {...event, if (applied) 'status': '報名成功'},
    ];
  }
}

class DemoEventActions implements EventActions {
  @override
  Future<EventActionResult> register(CampusEvent event) async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    DemoEvents.registered.add(event.id);
    return const EventActionResult(true, '報名成功（示範模式，未送出到學校）');
  }

  @override
  Future<EventActionResult> cancel(CampusEvent event) async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    DemoEvents.registered.remove(event.id);
    return const EventActionResult(true, '已取消報名（示範模式，未送出到學校）');
  }

  @override
  Future<EventRegistrationForm> loadForm(CampusEvent event) async =>
      EventRegistrationForm.fromJson({
        'tel': '0912345678',
        'email': 'demo@example.com',
        'memo': '',
        'food': [
          {'value': '1', 'label': '葷食', 'checked': true},
          {'value': '2', 'label': '素食', 'checked': false},
        ],
        'proof': [
          {'value': '1', 'label': '需要多元認證', 'checked': true},
          {'value': '0', 'label': '不需要', 'checked': false},
        ],
        'info': [
          ['身份', '學生'],
          ['班級', '資工三'],
          ['學號', 'niulifedemo'],
          ['姓名', '示範同學'],
        ],
      });

  @override
  Future<EventActionResult> save(
    CampusEvent event, {
    required String tel,
    required String email,
    required String memo,
    String? food,
    String? proof,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    return const EventActionResult(true, '已儲存修改（示範模式，未送出到學校）');
  }

  @override
  Future<List<CampusEvent>> registrations() async => [
    for (final e in DemoEvents.list(applied: true)) CampusEvent.fromJson(e),
  ];
}

// ── M 園區 ───────────────────────────────────────────────────────────────

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

// ── 圖書館 ───────────────────────────────────────────────────────────────

class DemoLibraryRepository extends LibraryRepository {
  DemoLibraryRepository() : super(schoolClient('https://sso.niu.edu.tw'));

  @override
  Future<Uint8List> image(String account, LibraryCodeKind kind) async {
    final data = await rootBundle.load(
      kind == LibraryCodeKind.entrance
          ? 'assets/demo/qr_entrance.png'
          : 'assets/demo/qr_borrow.png',
    );
    return data.buffer.asUint8List();
  }
}

// ── 郵件包裹 ─────────────────────────────────────────────────────────────

class DemoPostalService extends PostalService {
  @override
  Future<PostalPage> search(PostalQuery query) async {
    final q = query.normalized;
    if (!q.canSearch) {
      throw const PostalException('請填寫收件人、手機號碼或郵件號碼其中一項。');
    }
    await Future<void>.delayed(const Duration(milliseconds: 400));
    return PostalPage(
      records: [
        for (final r in DemoData.postal)
          if (r['status'] == q.status.name)
            PostalRecord(
              sequence: r['sequence']!,
              receivedDate: r['receivedDate']!,
              trackingNumber: r['trackingNumber']!,
              unit: r['unit']!,
              recipient: q.name.isEmpty ? '示範同學' : q.name,
              category: r['category']!,
              quantity: r['quantity']!,
              signature: r['signature']!,
              completedDate: r['completedDate']!,
              note: '',
              status: q.status,
            ),
      ],
      query: q,
      pageIndex: 0,
      pageCount: 1,
    );
  }

  @override
  Future<PostalPage> nextPage(PostalPage page) async =>
      throw const PostalException('沒有更多結果');
}

// ── 申請請假 ─────────────────────────────────────────────────────────────

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
    'reason': '',
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
  Future<LeaveApplicationData> initialize() async =>
      const LeaveApplicationData(revision: 'demo:0', notice: '請假注意事項');

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
    return const LeaveSubmitResult(
      applicationId: 'DEMO-0001',
      message: '示範模式：已模擬送出，沒有傳送到學校請假系統。',
    );
  }

  @override
  void dispose() {}
}
