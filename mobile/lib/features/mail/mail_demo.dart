import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';

import '../../core/demo/demo_documents.dart';
import 'mail_models.dart';
import 'numail_client.dart';

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
