import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/core/session/campus_session.dart';
import 'package:niu_mobile/features/demo/demo_services.dart';
import 'package:niu_mobile/features/mail/mail_body_view.dart';
import 'package:niu_mobile/features/mail/mail_captcha.dart';
import 'package:niu_mobile/features/mail/mail_models.dart';
import 'package:niu_mobile/features/mail/mail_screen.dart';
import 'package:niu_mobile/features/mail/mail_session.dart';
import 'package:niu_mobile/features/mail/numail_client.dart';
import 'package:niu_mobile/shared/shared.dart';

import 'features/authentication_session_test.dart' show MemoryVault;

/// Replays NUMail by method and path.
class NumailAdapter implements HttpClientAdapter {
  NumailAdapter(this.reply);
  final Object? Function(RequestOptions request, String? body) reply;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    String? body;
    if (requestStream != null) {
      body = utf8.decode(
        await requestStream.expand((c) => c).toList(),
        allowMalformed: true,
      );
    }
    final result = reply(options, body);
    if (result is Exception) throw result;
    if (result is ResponseBody) return result;
    return ResponseBody.fromString(
      result is String ? result : jsonEncode(result),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody status(int code, [String message = '']) => ResponseBody.fromString(
  jsonEncode({
    'error': {'message': message},
  }),
  code,
  headers: {
    Headers.contentTypeHeader: ['application/json'],
  },
);

NumailClient client(NumailAdapter adapter, {Map<String, String>? cookies}) =>
    NumailClient(cookies: cookies)..dio.httpClientAdapter = adapter;

void main() {
  group('models', () {
    test('dates, folders and addresses', () {
      expect(
        parseMailDate('Thu Oct 01 2026 22:12:59 GMT+0800 (台北標準時間)'),
        DateTime.utc(2026, 10, 1, 14, 12, 59),
      );
      expect(
        parseMailDate('2026-10-01T14:12:59Z'),
        DateTime.utc(2026, 10, 1, 14, 12, 59),
      );
      expect(parseMailDate(''), isNull);
      expect(encodeBox('INBOX'), 'SU5CT1g');
      expect(encodeBox('專題/資料'), isNot(contains('=')));
      final a = MailAddress.parse('王小明 <b123@ms.niu.edu.tw>');
      expect((a.name, a.address, a.valid), ('王小明', 'b123@ms.niu.edu.tw', true));
      expect(MailAddress.parse('not-an-address').valid, isFalse);
      expect(const MailFolder('Sent').label, '寄件備份');
    });

    MailMessage original() => MailMessage.fromJson({
      'uid': 7,
      'box': 'INBOX',
      'subject': 'Fwd: 專題討論',
      'sender': [
        {'name': '林老師', 'address': 'teacher@niu.edu.tw'},
      ],
      'receiver': [
        {'name': '我', 'address': 'b123@ms.niu.edu.tw'},
        {'name': '同學', 'address': 'b456@ms.niu.edu.tw'},
      ],
      'cc': [
        {'name': '助教', 'address': 'ta@niu.edu.tw'},
      ],
      'body': '<p>星期四<b>下午</b>見</p><img src="cid:pic1">',
      'messageId': '<m7@niu>',
      'references': '<m6@niu>',
      'attachments': [
        {'id': 1, 'partId': '2', 'filename': 'a.pdf', 'size': 10},
        {'id': 2, 'partId': '3', 'filename': 'p.png', 'cid': 'pic1', 'size': 5},
      ],
      'flags': [r'\Seen'],
    });

    test('reply, reply-all and forward are pre-filled like the site', () {
      final m = original();
      expect(m.files.map((f) => f.filename), ['a.pdf']);
      final reply = MailDraftData.answer(
        m,
        ComposeKind.reply,
        me: 'b123@ms.niu.edu.tw',
        dateLabel: '2026/10/1',
      );
      expect(reply.subject, 'Re: 專題討論');
      expect(reply.to.map((a) => a.address), ['teacher@niu.edu.tw']);
      expect(reply.cc, isEmpty);
      expect(reply.inReplyTo, '<m7@niu>');
      expect(reply.references, ['<m6@niu>', '<m7@niu>']);
      expect(reply.forwardAttachments.map((a) => a.id), [2]);
      expect(reply.quote, contains('<blockquote'));

      final all = MailDraftData.answer(
        m,
        ComposeKind.replyAll,
        me: 'b123@ms.niu.edu.tw',
        dateLabel: '',
      );
      expect(all.cc.map((a) => a.address), [
        'ta@niu.edu.tw',
        'b456@ms.niu.edu.tw',
      ]);

      final forward = MailDraftData.answer(
        m,
        ComposeKind.forward,
        me: 'b123@ms.niu.edu.tw',
        dateLabel: '',
      );
      expect(forward.subject, 'Fwd: 專題討論');
      expect(forward.to, isEmpty);
      expect(forward.forwardAttachments, hasLength(2));
      expect(forward.quote, contains('Forwarded message'));

      final json = MailDraftData(
        to: [const MailAddress('x@ms.niu.edu.tw')],
        subject: 'Hi',
        text: '第一行\n<第二行>',
        type: 'reply',
      ).toJson();
      expect(json['receiver'], [
        {'name': '', 'address': 'x@ms.niu.edu.tw'},
      ]);
      expect(json['body'], contains('第一行<br>&lt;第二行&gt;'));
      expect(json['type'], 'reply');
    });

    test('message html is sanitized before display', () {
      final clean = sanitizeMailHtml(
        '<p onclick="steal()">hi</p><script>bad()</script>'
        '<a href="javascript:bad()">x</a><iframe src="https://e.com"></iframe>'
        '<img src="https://tracker.example/p.gif">',
      );
      expect(clean, isNot(contains('script')));
      expect(clean, isNot(contains('onclick')));
      expect(clean, isNot(contains('javascript:')));
      expect(clean, isNot(contains('iframe')));
      expect(clean, contains('<p>hi</p>'));
      expect(hasRemoteImages(clean), isTrue);
      expect(
        hasRemoteImages('<img src="https://ms.niu.edu.tw/api/x">'),
        isFalse,
      );
    });
  });

  group('captcha', () {
    test('the school code renders as six glyphs without noise lines', () async {
      final svg = File('test/fixtures/numail_captcha.svg').readAsStringSync();
      final shape = CaptchaShape.parse(svg);
      expect(shape.glyphs, hasLength(6));
      expect((shape.width, shape.height), (150, 50));
      final png = await shape.png();
      expect(png.sublist(1, 4), utf8.encode('PNG'));
      expect(
        () => CaptchaShape.parse('<svg viewBox="0,0,1,1"><script/></svg>'),
        throwsA(isA<MailException>()),
      );
      expect(captchaCandidate(' Ab 12 3c '), 'Ab123c');
      expect(captchaCandidate('Ab12'), isNull);
      expect(captchaCandidate('Ab12-3c'), isNull);
    });
  });

  group('client', () {
    test('sign-in sends the site format and verifies the account', () async {
      String? loginBody;
      final adapter = NumailAdapter((r, body) {
        expect(r.headers['X-XSRF-TOKEN'], isNotEmpty);
        expect(
          r.headers['Cookie'],
          contains('XSRF-TOKEN=${r.headers['X-XSRF-TOKEN']}'),
        );
        return switch (r.path) {
          '/api/config/NUMail' => {'LOGIN_NEED_VERIFICATION_CODE': true},
          '/api/auth/captcha' => ResponseBody.fromString(
            '<svg viewBox="0,0,10,10"></svg>',
            200,
          ),
          '/api/auth/login' => () {
            loginBody = body;
            return ResponseBody.fromString(
              '{}',
              200,
              headers: {
                'set-cookie': ['SESSIONID=s1; Path=/; HttpOnly'],
                Headers.contentTypeHeader: ['application/json'],
              },
            );
          }(),
          '/api/auth/user' => {'username': 'B123'},
          _ => throw StateError(r.path),
        };
      });
      final web = client(adapter);
      expect(await web.captcha(), contains('<svg'));
      await web.login('b123', 'pässword', 'Ab12Cd');
      expect(jsonDecode(loginBody!), {
        'username': 'b123',
        'password': base64.encode(utf8.encode('pässword')),
        'captcha': 'Ab12Cd',
      });
      expect(web.cookies['SESSIONID'], 's1');
      expect(adapter.requests.last.headers['Cookie'], contains('SESSIONID=s1'));
    });

    test('sign-in failures are told apart', () async {
      Future<Object?> fail(ResponseBody response) async {
        final web = client(
          NumailAdapter((r, _) => r.path == '/api/auth/login' ? response : {}),
        );
        try {
          await web.login('b123', 'x', 'y');
        } catch (e) {
          return e;
        }
        return null;
      }

      expect(
        await fail(status(400, 'Validation Failed')),
        isA<MailWrongCaptcha>(),
      );
      expect(await fail(status(401, 'Unauthorized')), isA<MailWrongPassword>());
      expect(
        await fail(status(401, 'two factor authentication require')),
        isA<MailTwoFactorRequired>(),
      );
      expect(
        await fail(status(403, 'please change password first')),
        isA<MailMoreVerification>(),
      );
    });

    test('folders, lists and messages', () async {
      final adapter = NumailAdapter(
        (r, _) => switch (r.path) {
          '/api/box' => {
            'boxes': {
              'Trash': {'attribs': [], 'unseen': 0, 'children': null},
              'INBOX': {
                'attribs': [],
                'unseen': 3,
                'children': {
                  '專題': {'attribs': [], 'unseen': 1, 'children': null},
                },
              },
              'Sent': {'attribs': [], 'unseen': 0, 'children': null},
            },
          },
          '/api/mails/box/SU5CT1g' => {
            'total': 41,
            'mails': [
              {
                'uid': 9,
                'subject': ' 期中考 ',
                'sender': [
                  {'name': '系辦', 'address': 'csie@niu.edu.tw'},
                ],
                'receiver': [],
                'date': 'Thu Oct 01 2026 09:00:00 GMT+0800 (台北標準時間)',
                'text': 'line1\n line2',
                'flags': [r'\Seen'],
                'hasAttachment': true,
              },
            ],
          },
          '/api/mails/box/SU5CT1g/9' => {
            'mailGroup': [
              {'uid': 9, 'subject': '期中考', 'body': '', 'text': 'a\nb'},
            ],
          },
          _ => throw StateError(r.path),
        },
      );
      final web = client(adapter);
      final folders = await web.folders();
      expect(folders.map((f) => f.name), [
        'INBOX',
        'Sent',
        'Trash',
        'INBOX/專題',
      ]);
      final page = await web.list('INBOX');
      expect(adapter.requests.last.queryParameters, {
        'page': 1,
        'sort': 'date',
        'asc': false,
      });
      expect(page.total, 41);
      expect(page.hasMore, isTrue);
      final m = page.mails.single;
      expect(
        (m.subject, m.seen, m.preview, m.hasAttachment),
        ('期中考', true, 'line1 line2', true),
      );
      final full = await web.open('INBOX', 9);
      expect(full.html, 'a<br>b');
      expect(full.box, 'INBOX');
    });

    test('search uses the full-text field of the folder', () async {
      final adapter = NumailAdapter((r, _) => {'mails': [], 'total': 0});
      await client(adapter).list('INBOX', query: ' 期中 ');
      expect(adapter.requests.single.path, '/api/mails/search');
      expect(adapter.requests.single.queryParameters['all'], '期中');
      expect(adapter.requests.single.queryParameters['box'], 'SU5CT1g');
    });

    test(
      'a lost reply to sending is uncertain; a lost session is not',
      () async {
        final drop = client(
          NumailAdapter(
            (r, _) => DioException.receiveTimeout(
              timeout: const Duration(seconds: 1),
              requestOptions: r,
            ),
          ),
        );
        await expectLater(
          drop.send(MailDraft('d1'), MailDraftData(subject: 'x')),
          throwsA(isA<MailUncertain>()),
        );
        final expired = client(NumailAdapter((r, _) => status(401)));
        await expectLater(
          expired.list('INBOX'),
          throwsA(isA<MailSignInRequired>()),
        );
        expect(await expired.signedInAs(), isNull);
      },
    );
  });

  group('session', () {
    test('restore needs the same account and a live session', () async {
      final vault = MemoryVault();
      final session = CampusSession(vault: vault, platformCleanup: [])
        ..account = 'b123';
      addTearDown(session.dispose);
      var user = 'b123';
      Map<String, String>? sent;
      final store = MailSession(
        session,
        client: (cookies) {
          sent = cookies;
          return client(
            NumailAdapter((r, _) => {'username': user}),
            cookies: cookies,
          );
        },
      );
      expect(await store.restore(), isNull);
      await vault.write(
        MailSession.key,
        jsonEncode({
          'account': 'b999',
          'cookies': {'SESSIONID': 'x'},
        }),
      );
      expect(await store.restore(), isNull);
      await vault.write(
        MailSession.key,
        jsonEncode({
          'account': 'b123',
          'cookies': {'SESSIONID': 'x'},
        }),
      );
      expect(await store.restore(), isNotNull);
      expect(sent?['SESSIONID'], 'x');
      user = 'b999';
      expect(await store.restore(), isNull);
    });

    test(
      'automatic sign-in retries unreadable or wrong codes three times',
      () async {
        final session = CampusSession(vault: MemoryVault(), platformCleanup: [])
          ..account = 'b123';
        addTearDown(session.dispose);
        var logins = 0;
        final svg = File('test/fixtures/numail_captcha.svg').readAsStringSync();
        final guesses = [null, 'AAAAAA', 'BBBBBB'];
        var read = 0;
        final store = MailSession(
          session,
          reader: (_) async => guesses[read++],
          client: (_) => client(
            NumailAdapter(
              (r, _) => switch (r.path) {
                '/api/config/NUMail' => {'LOGIN_NEED_VERIFICATION_CODE': true},
                '/api/auth/captcha' => ResponseBody.fromString(svg, 200),
                '/api/auth/login' => () {
                  logins++;
                  return logins == 1 ? status(400, 'captcha error') : {};
                }(),
                '/api/auth/user' => {'username': 'b123'},
                _ => throw StateError(r.path),
              },
            ),
          ),
        );
        final web = await store.automatic('pw');
        expect(web, isNotNull);
        expect((read, logins), (3, 2));
        expect(
          await session.vault.read(MailSession.key),
          contains('"account":"b123"'),
        );
      },
    );
  });

  testWidgets('demo: read, reply, then delete', (tester) async {
    DemoMailService.reset();
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final session = CampusSession(vault: MemoryVault(), platformCleanup: [])
      ..account = 'niulifedemo';
    addTearDown(session.dispose);
    DateTime now() => DateTime.utc(2026, 10, 1, 6);
    await tester.pumpWidget(
      MaterialApp(
        theme: NiuTheme.light,
        home: MailScreen(
          session: session,
          service: DemoMailService(now: now),
          now: now,
          bodyBuilder: (m, _) => Text('BODY ${htmlToText(m.html)}'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('收件匣 2'), findsOneWidget);
    expect(find.text('期中考試時間公告'), findsOneWidget);

    await tester.tap(find.text('期中考試時間公告'));
    await tester.pumpAndSettle();
    expect(find.textContaining('BODY 各位同學好'), findsOneWidget);
    expect(find.text('期中考時間表.pdf'), findsOneWidget);

    await tester.tap(find.text('回覆'));
    await tester.pumpAndSettle();
    expect(find.text('Re: 期中考試時間公告'), findsOneWidget);
    expect(find.text('資訊工程學系'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, '內容'), '收到，謝謝！');
    await tester.tap(find.text('寄出'));
    await tester.pumpAndSettle();
    expect(find.text('已寄出'), findsOneWidget);

    await tester.tap(find.byTooltip('刪除'));
    await tester.pumpAndSettle();
    expect(find.text('期中考試時間公告'), findsNothing);
    expect(find.text('收件匣 1'), findsOneWidget);

    await tester.tap(find.text('寄件備份'));
    await tester.pumpAndSettle();
    expect(find.text('Re: 期中考試時間公告'), findsOneWidget);
    await tester.tap(find.text('垃圾桶'));
    await tester.pumpAndSettle();
    expect(find.text('期中考試時間公告'), findsOneWidget);
  });
}
