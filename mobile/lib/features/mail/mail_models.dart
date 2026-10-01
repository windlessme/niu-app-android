import 'dart:convert';
import 'dart:typed_data';

/// 校園信箱 (NUMail at ms.niu.edu.tw): folders, messages and drafts.

class MailAddress {
  const MailAddress(this.address, [this.name = '']);
  final String address, name;

  String get display => name.trim().isNotEmpty ? name.trim() : address;

  /// `王小明 <b123@ms.niu.edu.tw>` or a bare address.
  static MailAddress parse(String text) {
    final m = RegExp(r'^(.*)<([^<>]+)>\s*$').firstMatch(text.trim());
    if (m == null) return MailAddress(text.trim());
    return MailAddress(
      m[2]!.trim(),
      m[1]!.trim().replaceAll(RegExp(r'^"|"$'), ''),
    );
  }

  static MailAddress? from(Object? json) => json is Map
      ? MailAddress('${json['address'] ?? ''}'.trim(), '${json['name'] ?? ''}')
      : null;

  Map<String, String> toJson() => {'name': name, 'address': address};

  /// Same rule as the school's compose form.
  bool get valid => RegExp(
    r'^\w+((-\w+)|(\.\w+))*@[A-Za-z0-9]+((\.|-)[A-Za-z0-9]+)*\.[A-Za-z]+$',
  ).hasMatch(address.trim());

  @override
  bool operator ==(Object other) =>
      other is MailAddress &&
      other.address.toLowerCase() == address.toLowerCase();

  @override
  int get hashCode => address.toLowerCase().hashCode;
}

List<MailAddress> addressList(Object? json) => [
  if (json is List)
    for (final item in json)
      if (MailAddress.from(item) case final a? when a.address.isNotEmpty) a,
];

/// The site addresses folders by base64url of the IMAP name.
String encodeBox(String box) =>
    base64Url.encode(utf8.encode(box)).replaceAll('=', '');

class MailFolder {
  const MailFolder(this.name, {this.unseen = 0, this.attributes = const []});
  final String name;
  final int unseen;
  final List<String> attributes;

  static const inbox = 'INBOX', sent = 'Sent', drafts = 'Drafts';
  static const trash = 'Trash';

  String get label => switch (name) {
    inbox => '收件匣',
    sent => '寄件備份',
    drafts => '草稿',
    trash => '垃圾桶',
    'Junk' || 'Spam' => '垃圾郵件',
    _ => name.split('/').last,
  };

  /// Inbox first, then the system folders, then the reader's own.
  int get order => switch (name) {
    inbox => 0,
    drafts => 1,
    sent => 2,
    trash => 3,
    _ => 4,
  };
}

/// `Thu Oct 01 2026 22:12:59 GMT+0800 (台北標準時間)` or ISO 8601.
DateTime? parseMailDate(Object? value) {
  final text = '${value ?? ''}'.trim();
  if (text.isEmpty) return null;
  final iso = DateTime.tryParse(text);
  if (iso != null) return iso.toUtc();
  final m = RegExp(
    r'^\w{3} (\w{3}) (\d{1,2}) (\d{4}) (\d{2}):(\d{2}):(\d{2}) GMT([+-])(\d{2})(\d{2})',
  ).firstMatch(text);
  if (m == null) return null;
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final month = months.indexOf(m[1]!) + 1;
  if (month == 0) return null;
  final offset = Duration(hours: int.parse(m[8]!), minutes: int.parse(m[9]!));
  final local = DateTime.utc(
    int.parse(m[3]!),
    month,
    int.parse(m[2]!),
    int.parse(m[4]!),
    int.parse(m[5]!),
    int.parse(m[6]!),
  );
  return m[7] == '+' ? local.subtract(offset) : local.add(offset);
}

/// A row of a folder listing.
class MailSummary {
  const MailSummary({
    required this.uid,
    required this.box,
    required this.subject,
    required this.from,
    required this.to,
    required this.date,
    required this.preview,
    required this.flags,
    required this.hasAttachment,
  });
  final int uid;
  final String box, subject, preview;
  final List<MailAddress> from, to;
  final DateTime? date;
  final List<String> flags;
  final bool hasAttachment;

  bool get seen => flags.any((f) => f.contains('Seen'));
  bool get flagged => flags.any((f) => f.contains('Flagged'));

  MailSummary withFlags(List<String> next) => MailSummary(
    uid: uid,
    box: box,
    subject: subject,
    from: from,
    to: to,
    date: date,
    preview: preview,
    flags: next,
    hasAttachment: hasAttachment,
  );

  static MailSummary fromJson(Map json, String fallbackBox) => MailSummary(
    uid: json['uid'] is int ? json['uid'] as int : 0,
    box: '${json['box'] ?? fallbackBox}'.isEmpty
        ? fallbackBox
        : '${json['box'] ?? fallbackBox}',
    subject: '${json['subject'] ?? ''}'.trim(),
    from: addressList(json['sender']),
    to: addressList(json['receiver']),
    date: parseMailDate(json['date']),
    preview: '${json['text'] ?? ''}'.replaceAll(RegExp(r'\s+'), ' ').trim(),
    flags: [
      if (json['flags'] is List)
        for (final f in json['flags'] as List) '$f',
    ],
    hasAttachment: json['hasAttachment'] == true,
  );
}

class MailPage {
  const MailPage(this.mails, this.total, this.page);
  final List<MailSummary> mails;
  final int total, page;
  bool get hasMore => page * 20 < total && mails.isNotEmpty;
}

class MailAttachment {
  const MailAttachment({
    required this.id,
    required this.partId,
    required this.filename,
    required this.contentType,
    required this.size,
    this.cid = '',
  });
  final int id;
  final String partId, filename, contentType, cid;
  final int size;

  /// Pictures embedded in the body, not files the sender attached.
  bool inlineIn(String body) =>
      cid.isNotEmpty && (body.contains('cid:$cid') || body.contains(cid));

  static MailAttachment fromJson(Map json) => MailAttachment(
    id: json['id'] is int ? json['id'] as int : 0,
    partId: '${json['partId'] ?? ''}',
    filename: '${json['filename'] ?? ''}'.trim().isEmpty
        ? '附件'
        : '${json['filename']}'.trim(),
    contentType: '${json['contentType'] ?? 'application/octet-stream'}',
    size: json['size'] is int ? json['size'] as int : 0,
    cid: '${json['cid'] ?? ''}',
  );
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
}

/// One opened message.
class MailMessage {
  const MailMessage({
    required this.uid,
    required this.box,
    required this.subject,
    required this.from,
    required this.to,
    required this.cc,
    required this.bcc,
    required this.date,
    required this.html,
    required this.flags,
    required this.attachments,
    required this.messageId,
    required this.references,
  });
  final int uid;
  final String box, subject, html, messageId;
  final List<MailAddress> from, to, cc, bcc;
  final DateTime? date;
  final List<String> flags, references;
  final List<MailAttachment> attachments;

  bool get seen => flags.any((f) => f.contains('Seen'));

  List<MailAttachment> get files => [
    for (final a in attachments)
      if (!a.inlineIn(html)) a,
  ];

  static MailMessage fromJson(Map json) {
    final body = '${json['body'] ?? ''}';
    final text = '${json['text'] ?? ''}';
    final refs = json['references'];
    return MailMessage(
      uid: json['uid'] is int ? json['uid'] as int : 0,
      box: '${json['box'] ?? ''}',
      subject: '${json['subject'] ?? ''}'.trim(),
      from: addressList(json['sender']),
      to: addressList(json['receiver']),
      cc: addressList(json['cc']),
      bcc: addressList(json['bcc']),
      date: parseMailDate(json['date']),
      html: body.trim().isNotEmpty ? body : plainToHtml(text),
      flags: [
        if (json['flags'] is List)
          for (final f in json['flags'] as List) '$f',
      ],
      attachments: [
        if (json['attachments'] is List)
          for (final a in json['attachments'] as List)
            if (a is Map) MailAttachment.fromJson(a),
      ],
      messageId: '${json['messageId'] ?? ''}',
      references: refs is String
          ? [if (refs.isNotEmpty) refs]
          : [
              if (refs is List)
                for (final r in refs) '$r',
            ],
    );
  }
}

String escapeHtml(String text) =>
    const HtmlEscape(HtmlEscapeMode.element).convert(text);

String plainToHtml(String text) =>
    escapeHtml(text).replaceAll('\r\n', '\n').replaceAll('\n', '<br>');

// ── Compose ────────────────────────────────────────────────────────────────

enum ComposeKind { fresh, reply, replyAll, forward, draft }

/// Fields of a message being written. [quote] is the original message's HTML
/// for replies and forwards, kept apart from what the student types.
class MailDraftData {
  MailDraftData({
    this.to = const [],
    this.cc = const [],
    this.bcc = const [],
    this.subject = '',
    this.text = '',
    this.quote = '',
    this.type,
    this.inReplyTo,
    this.references = const [],
    this.forwardAttachments = const [],
  });
  final List<MailAddress> to, cc, bcc;
  final String subject, text, quote;

  /// `reply` / `forward`, as the site records it.
  final String? type;
  final String? inReplyTo;
  final List<String> references;

  /// The original's attachments carried into a forward (or inline images
  /// into a reply).
  final List<MailAttachment> forwardAttachments;

  /// Body sent to the site: the typed text, then any quoted original.
  String get html => [
    '<div>${plainToHtml(text)}</div>',
    if (quote.isNotEmpty) quote,
  ].join('<br>');

  Map<String, Object?> toJson() => {
    'receiver': [for (final a in to) a.toJson()],
    'cc': [for (final a in cc) a.toJson()],
    'bcc': [for (final a in bcc) a.toJson()],
    'subject': subject,
    'type': ?type,
    'body': '<head></head><body>$html</body>',
  };

  bool get isEmpty =>
      to.isEmpty &&
      cc.isEmpty &&
      bcc.isEmpty &&
      subject.trim().isEmpty &&
      text.trim().isEmpty &&
      quote.isEmpty;

  /// Pre-filled reply, reply-all or forward of [m] for [me].
  static MailDraftData answer(
    MailMessage m,
    ComposeKind kind, {
    required String me,
    required String dateLabel,
  }) {
    final references = [
      ...m.references,
      if (m.messageId.isNotEmpty) m.messageId,
    ];
    final inReplyTo = m.messageId.isEmpty ? null : m.messageId;
    final mine = me.toLowerCase();
    if (kind == ComposeKind.forward) {
      return MailDraftData(
        subject: _prefixed(m.subject, 'Fwd:', 'Re:'),
        type: 'forward',
        inReplyTo: inReplyTo,
        references: references,
        quote:
            '<div>---------- Forwarded message ---------<br>'
            'From: ${escapeHtml(_joined(m.from))}<br>'
            'Date: ${escapeHtml(dateLabel)}<br>'
            'Subject: ${escapeHtml(m.subject)}<br>'
            'To: ${escapeHtml(_joined(m.to))}<br><br>'
            '${m.html}</div>',
        forwardAttachments: m.attachments,
      );
    }
    final fromMe =
        m.from.isNotEmpty && m.from.first.address.toLowerCase() == mine;
    final to = fromMe ? m.to : m.from.take(1).toList();
    final cc = kind == ComposeKind.replyAll
        ? <MailAddress>{
            for (final a in [...m.cc, if (!fromMe) ...m.to])
              if (a.address.toLowerCase() != mine && !to.contains(a)) a,
          }.toList()
        : <MailAddress>[];
    final sender = m.from.isEmpty ? '' : m.from.first.address;
    return MailDraftData(
      to: to,
      cc: cc,
      subject: _prefixed(m.subject, 'Re:', 'Fwd:'),
      type: 'reply',
      inReplyTo: inReplyTo,
      references: references,
      quote:
          '<div>${escapeHtml('$dateLabel，$sender 寫道：')}</div>'
          '<blockquote style="margin:0 0 0 .8ex;border-left:1px solid #ccc;padding-left:1ex">'
          '${m.html}</blockquote>',
      // Only the pictures inside the quoted text travel with a reply.
      forwardAttachments: [
        for (final a in m.attachments)
          if (a.cid.isNotEmpty) a,
      ],
    );
  }

  static String _joined(List<MailAddress> list) => list
      .map((a) => a.name.isEmpty ? a.address : '${a.name} <${a.address}>')
      .join(', ');

  static String _prefixed(String subject, String prefix, String other) {
    if (subject.contains(prefix)) return subject;
    if (subject.contains(other)) return subject.replaceFirst(other, prefix);
    return '$prefix $subject'.trim();
  }
}

/// A server-side draft and the files already attached to it.
class MailDraft {
  MailDraft(this.id, {List<MailAttachment>? attachments})
    : attachments = attachments ?? [];
  final String id;
  final List<MailAttachment> attachments;
}

// ── Sign-in ────────────────────────────────────────────────────────────────

class MailCaptcha {
  const MailCaptcha(this.svg, this.png);
  final String svg;
  final Uint8List png;
}

class MailException implements Exception {
  const MailException(this.message);
  final String message;
  @override
  String toString() => message;
}

class MailSignInRequired extends MailException {
  const MailSignInRequired() : super('信箱登入已失效，請重新登入。');
}

class MailWrongPassword extends MailException {
  const MailWrongPassword() : super('帳號或密碼不正確。');
}

class MailWrongCaptcha extends MailException {
  const MailWrongCaptcha() : super('驗證碼不正確，請輸入新的驗證碼。');
}

class MailTwoFactorRequired extends MailException {
  const MailTwoFactorRequired() : super('學校要求二次驗證，請輸入驗證碼。');
}

class MailMoreVerification extends MailException {
  const MailMoreVerification() : super('學校要求變更密碼或額外驗證，請先到學校信箱網站完成。');
}

/// A change was sent but its result is unknown; never resend blindly.
class MailUncertain extends MailException {
  const MailUncertain() : super('還無法確認信件是否已寄出。請先查看「寄件備份」，確認沒有寄出再重寄。');
}
