import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';

import '../../core/demo/demo_account.dart';
import '../../core/demo/demo_data.dart';
import '../../core/network/school_clients.dart';
import '../../core/time/campus_date.dart';
import '../events/event_actions.dart';
import '../events/events_screen.dart';
import '../leave/leave_application_data.dart';
import '../leave/leave_application_service.dart';
import '../library/library_repository.dart';
import '../library/space_models.dart';
import '../mail/mail_models.dart';
import '../mail/numail_client.dart';
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

/// Demo result text; store screenshots show what a student would see.
String _note(String text) => storeScreenshots ? text : '$text（示範模式，未送出到學校）';

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
    return EventActionResult(true, _note('報名成功'));
  }

  @override
  Future<EventActionResult> cancel(CampusEvent event) async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    DemoEvents.registered.remove(event.id);
    return EventActionResult(true, _note('已取消報名'));
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
          ['姓名', DemoData.studentName],
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
    return EventActionResult(true, _note('已儲存修改'));
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
              recipient: q.name.isEmpty ? DemoData.studentName : q.name,
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

// ── 圖書館設備預約 ───────────────────────────────────────────────────────

/// Sample rooms with a few fixed bookings; reservations live in memory.
class DemoSpaceService implements SpaceService {
  DemoSpaceService();
  static final _reserved = <SpaceReservation>[];
  static var _nextId = 900;

  static const _groups = [
    SpaceGroup(5, '宜思智慧小間', total: 3),
    SpaceGroup(6, 'Switch相關設備', total: 1),
    SpaceGroup(8, '臨時研究小間', total: 2),
    SpaceGroup(10, '大型討論室', total: 3),
  ];
  static const _rooms = {
    5: [
      SpaceRoom(56, 'iSmart 504'),
      SpaceRoom(57, 'iSmart 505'),
      SpaceRoom(58, 'iSmart 506'),
    ],
    6: [SpaceRoom(59, 'Switch')],
    8: [SpaceRoom(61, '509研究小間'), SpaceRoom(67, '510研究小間')],
    10: [
      SpaceRoom(63, '523討論室'),
      SpaceRoom(64, '612討論室'),
      SpaceRoom(65, '314討論室'),
    ],
  };

  @override
  Future<bool> signedIn() async => true;

  @override
  Future<List<SpaceGroup>> groups() async => _groups;

  @override
  Future<SpaceSchedule> schedule(SpaceGroup group, CampusDate date) async {
    final rooms = _rooms[group.id] ?? const <SpaceRoom>[];
    final seed = date.day + group.id;
    return SpaceSchedule(
      group: group,
      date: date,
      rooms: rooms,
      bookings: [
        for (final (i, room) in rooms.indexed)
          if ((seed + i) % 3 != 0)
            SpaceBooking(
              roomId: room.id,
              start: (9 + (seed + i * 5) % 9) * 60,
              end: (11 + (seed + i * 5) % 9) * 60 + 30,
            ),
        for (final r in _reserved)
          if (r.date == date && rooms.any((room) => room.id == r.roomId))
            SpaceBooking(
              roomId: r.roomId,
              start: r.start,
              end: r.end,
              mine: true,
            ),
      ],
    );
  }

  @override
  Future<SpaceRules> rules(
    SpaceGroup group,
    SpaceRoom room,
    CampusDate date,
  ) async {
    final used = _reserved.fold<int>(0, (sum, r) => sum + r.minutes);
    return SpaceRules(
      open: group.id == 5 || group.id == 6 ? 8 * 60 : 8 * 60 + 30,
      close: 21 * 60 + 30,
      minHours: 1,
      maxHours: group.id == 6 ? 2 : 4,
      remainingHours: 28 - used / 60,
    );
  }

  @override
  Future<List<SpaceReservation>> mine() async => List.of(_reserved);

  @override
  Future<void> reserve(
    SpaceGroup group,
    SpaceRoom room,
    CampusDate date,
    Minute start,
    Minute end,
  ) async {
    final current = await schedule(group, date);
    if (!current.isFree(room.id, start, end)) {
      throw const SpaceException('這個時段已經有人預約或不開放。');
    }
    _reserved.add(
      SpaceReservation(
        id: _nextId++,
        roomId: room.id,
        roomName: room.name,
        date: date,
        start: start,
        endDate: date,
        end: end,
        state: ReservationState.reserved,
        keepUntil: (date, start + 15),
      ),
    );
  }

  @override
  Future<void> cancel(SpaceReservation reservation) async =>
      _reserved.removeWhere((r) => r.id == reservation.id);

  @override
  void close() {}

  /// Test hook: start every run from an empty list.
  @visibleForTesting
  static void reset() => _reserved.clear();
}

// ── 校園信箱 ─────────────────────────────────────────────────────────────

/// Sample mailbox; reading, moving, drafts and sending stay in memory.
class DemoMailService implements MailService {
  DemoMailService({DateTime Function()? now}) : now = now ?? DateTime.now;
  final DateTime Function() now;
  static final _boxes = <String, List<MailMessage>>{};
  static var _nextUid = 100;
  static var _nextDraft = 1;
  static final _drafts = <String, MailDraftData>{};

  static const me = MailAddress('niulifedemo@ms.niu.edu.tw', '示範同學');

  @visibleForTesting
  static void reset() {
    _boxes.clear();
    _drafts.clear();
  }

  void _seed() {
    if (_boxes.isNotEmpty) return;
    final t = now().toUtc();
    MailMessage mail(
      int uid,
      String subject,
      MailAddress from,
      Duration ago,
      String body, {
      bool seen = false,
      List<MailAttachment> files = const [],
    }) => MailMessage(
      uid: uid,
      box: MailFolder.inbox,
      subject: subject,
      from: [from],
      to: const [me],
      cc: const [],
      bcc: const [],
      date: t.subtract(ago),
      html: body,
      flags: [if (seen) r'\Seen'],
      attachments: files,
      messageId: '<demo-$uid@ms.niu.edu.tw>',
      references: const [],
    );
    _boxes[MailFolder.inbox] = [
      mail(
        6,
        '圖書資訊館電子報 第 128 期',
        const MailAddress('libnews@niu.edu.tw', '圖書資訊館'),
        const Duration(minutes: 10),
        '<table width="800" style="width:800px;border-collapse:collapse">'
            '<tr><td colspan="2" style="background:#0a62d0;color:#fff;padding:24px;font-size:24px">'
            '圖書資訊館電子報</td></tr>'
            '<tr><td style="width:400px;padding:16px;vertical-align:top">'
            '<h3>新書推薦</h3><p>本月新進館藏 320 冊，歡迎到二樓新書展示區借閱。</p></td>'
            '<td style="width:400px;padding:16px;vertical-align:top">'
            '<h3>討論室開放</h3><p>大型討論室 523、612、314 開放線上預約，每次 1–4 小時。</p></td></tr>'
            '</table>',
      ),
      mail(
        5,
        '【圖書館】設備預約提醒',
        const MailAddress('library@niu.edu.tw', '圖書資訊館'),
        const Duration(minutes: 40),
        '<p>您預約的 <b>523討論室</b> 將於今天 14:00 開始，請準時報到。</p>',
      ),
      mail(
        4,
        '期中考試時間公告',
        const MailAddress('csie@niu.edu.tw', '資訊工程學系'),
        const Duration(hours: 5),
        '<p>各位同學好：</p><p>期中考試將於第 9 週舉行，詳細時間請見附件。</p>',
        files: const [
          MailAttachment(
            id: 1,
            partId: '2',
            filename: '期中考時間表.pdf',
            contentType: 'application/pdf',
            size: 48213,
          ),
        ],
      ),
      mail(
        3,
        'Re: 專題討論時間',
        const MailAddress('b11200001@ms.niu.edu.tw', '林同學'),
        const Duration(days: 1, hours: 2),
        '<p>星期四下午三點可以嗎？我們在圖書館討論室見。</p>',
        seen: true,
      ),
      mail(
        2,
        '校園活動：資訊週開幕',
        const MailAddress('activity@niu.edu.tw', '課外活動組'),
        const Duration(days: 3),
        '<p>資訊週將於下週一開幕，歡迎同學踴躍參加。</p>',
        seen: true,
      ),
    ];
    _boxes[MailFolder.drafts] = [];
    _boxes[MailFolder.sent] = [];
    _boxes[MailFolder.trash] = [];
  }

  @override
  Map<String, String> get cookies => const {};

  @override
  Future<String?> signedInAs() async => 'niulifedemo';

  @override
  Future<List<MailFolder>> folders() async {
    _seed();
    return [
      for (final name in [
        MailFolder.inbox,
        MailFolder.drafts,
        MailFolder.sent,
        MailFolder.trash,
      ])
        MailFolder(name, unseen: _boxes[name]!.where((m) => !m.seen).length),
    ];
  }

  @override
  Future<MailPage> list(String box, {int page = 1, String query = ''}) async {
    _seed();
    final q = query.trim().toLowerCase();
    final mails = [
      for (final m in _boxes[box] ?? const <MailMessage>[])
        if (q.isEmpty ||
            '${m.subject} ${m.html} ${m.from.map((a) => a.display)}'
                .toLowerCase()
                .contains(q))
          m,
    ]..sort((a, b) => b.date!.compareTo(a.date!));
    return MailPage(
      [
        for (final m in mails.skip((page - 1) * 20).take(20))
          MailSummary(
            uid: m.uid,
            box: box,
            subject: m.subject,
            from: m.from,
            to: m.to,
            date: m.date,
            preview: htmlToText(m.html),
            flags: m.flags,
            hasAttachment: m.files.isNotEmpty,
          ),
      ],
      mails.length,
      page,
    );
  }

  MailMessage _find(String box, int uid) {
    _seed();
    return (_boxes[box] ?? const []).firstWhere(
      (m) => m.uid == uid,
      orElse: () => throw const MailException('找不到這封信'),
    );
  }

  MailMessage _with(MailMessage m, {String? box, List<String>? flags}) =>
      MailMessage(
        uid: m.uid,
        box: box ?? m.box,
        subject: m.subject,
        from: m.from,
        to: m.to,
        cc: m.cc,
        bcc: m.bcc,
        date: m.date,
        html: m.html,
        flags: flags ?? m.flags,
        attachments: m.attachments,
        messageId: m.messageId,
        references: m.references,
      );

  @override
  Future<MailMessage> open(String box, int uid) async => _find(box, uid);

  @override
  Future<void> setSeen(String box, List<int> uids, bool seen) async {
    final list = _boxes[box]!;
    for (var i = 0; i < list.length; i++) {
      if (uids.contains(list[i].uid)) {
        list[i] = _with(list[i], flags: [if (seen) r'\Seen']);
      }
    }
  }

  @override
  Future<void> move(String box, List<int> uids, String to) async {
    final moving = _boxes[box]!.where((m) => uids.contains(m.uid)).toList();
    _boxes[box]!.removeWhere((m) => uids.contains(m.uid));
    _boxes[to]!.addAll([for (final m in moving) _with(m, box: to)]);
  }

  @override
  Future<void> delete(String box, List<int> uids) async =>
      _boxes[box]!.removeWhere((m) => uids.contains(m.uid));

  @override
  Future<Uint8List> attachment(
    String box,
    int uid,
    MailAttachment file,
  ) async => demoPdf(file.filename);

  @override
  Future<MailDraft> newDraft({
    String? inReplyTo,
    List<String> references = const [],
  }) async => MailDraft('demo-${_nextDraft++}');

  @override
  Future<(MailDraft, MailDraftData)> openDraft(int uid) async {
    final m = _find(MailFolder.drafts, uid);
    return (
      MailDraft('demo-uid-$uid'),
      MailDraftData(to: m.to, subject: m.subject, text: htmlToText(m.html)),
    );
  }

  @override
  Future<MailAttachment> upload(
    MailDraft draft,
    String name,
    Uint8List bytes,
  ) async => MailAttachment(
    id: _nextUid++,
    partId: '',
    filename: name,
    contentType: 'application/octet-stream',
    size: bytes.length,
  );

  @override
  Future<MailAttachment> carry(
    MailDraft draft,
    MailAttachment original,
  ) async => original;

  @override
  Future<void> detach(MailDraft draft, MailAttachment file) async {}

  MailMessage _stored(String box, MailDraftData data, MailDraft draft) =>
      MailMessage(
        uid: _nextUid++,
        box: box,
        subject: data.subject,
        from: const [me],
        to: data.to,
        cc: data.cc,
        bcc: data.bcc,
        date: now().toUtc(),
        html: data.html,
        flags: const [r'\Seen'],
        attachments: draft.attachments,
        messageId: '',
        references: data.references,
      );

  @override
  Future<void> save(MailDraft draft, MailDraftData data) async {
    _seed();
    _drafts[draft.id] = data;
    _boxes[MailFolder.drafts]!.add(_stored(MailFolder.drafts, data, draft));
  }

  @override
  Future<void> send(MailDraft draft, MailDraftData data) async {
    _seed();
    _boxes[MailFolder.sent]!.add(_stored(MailFolder.sent, data, draft));
  }

  @override
  Future<void> discard(MailDraft draft) async => _drafts.remove(draft.id);

  @override
  void close() {}
}
