import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/features/authentication/school_login_capture.dart';
import 'package:niu_mobile/features/moodle/moodle_login_captcha.dart';
import 'package:niu_mobile/features/moodle/moodle_question_login.dart';

class FakePage implements QuestionLoginPage {
  final loads = <Uri>[];
  final runs = <String>[];

  /// Answers by the script's first line, e.g. 'find', 'capture', 'submit'.
  Object? Function(String kind, Map<String, Object?> args) answer = (_, _) =>
      null;

  @override
  Future<void> load(Uri url) async => loads.add(url);

  @override
  Future<Object?> run(String body, Map<String, Object?> arguments) async {
    final kind = body.contains('RadListView')
        ? 'find'
        : body.contains('toDataURL') && !body.contains('HTMLFormElement')
        ? 'capture'
        : 'submit';
    runs.add(kind);
    return answer(kind, arguments);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final target = Uri.parse('https://euni.niu.edu.tw/mod/quiz/view.php?id=7');
  final key = Uri.parse(
    'https://euni.niu.edu.tw/admin/tool/mobile/autologin.php?key=k',
  );
  final login = Uri.parse('https://euni.niu.edu.tw/login/index.php');
  final home = Uri.parse('https://euni.niu.edu.tw/my/');
  final std002 = Uri.parse('https://ccsys.niu.edu.tw/SSO/Std002.aspx');
  final ssoLogin = Uri.parse('https://ccsys1.niu.edu.tw/SSO/login');

  group('M 園區 login code', () {
    final samples = Directory(
      'test/fixtures/moodle_captcha',
    ).listSync().whereType<File>().toList();

    Future<(Uint8List, int, int)> rgba(File file) async {
      final codec = await ui.instantiateImageCodec(file.readAsBytesSync());
      final image = (await codec.getNextFrame()).image;
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      return (data!.buffer.asUint8List(), image.width, image.height);
    }

    test('the digit colour is found in every sample', () async {
      expect(samples, hasLength(8));
      for (final file in samples) {
        final (bytes, w, h) = await rgba(file);
        final mask = captchaDigitMask(bytes, w, h);
        expect(mask, isNotNull, reason: file.path);
        final ink = mask!.where((v) => v).length;
        // Five glyphs come to roughly 340–400 pixels at 180×40.
        expect(ink, inInclusiveRange(250, 420), reason: file.path);
      }
    });

    test('readings must be five digits and agree', () async {
      final png = samples.first.readAsBytesSync();
      var calls = 0;
      expect(
        await readMoodleCaptcha(png, read: (_) async => '3 4 7 4 8'),
        '34748',
      );
      expect(
        await readMoodleCaptcha(
          png,
          read: (_) async => ++calls == 1 ? '12345' : '34748',
        ),
        isNull,
      );
      expect(await readMoodleCaptcha(png, read: (_) async => ''), isNull);
    });

    test('look-alike letters map to digits', () {
      expect(captchaDigits('O9 3S8'), '09358');
      expect(captchaDigits('1234'), isNull);
      expect(captchaDigits('123456'), isNull);
    });
  });

  group('login recovery', () {
    late FakePage page;
    late List<String> events;
    QuestionLoginRecovery recovery({
      SubmittedSchoolCredentials? saved,
      bool refreshes = true,
      Uri? key,
    }) {
      QuestionLoginRecovery.euniLink = null;
      return QuestionLoginRecovery(
        target: target,
        autologin: () async => key ?? target,
        credentials: () async => saved,
        reauthorize: () async {
          events.add('reauthorize');
          return refreshes;
        },
        onManual: () => events.add('manual'),
        onTimeout: (m) => events.add('timeout'),
        readCaptcha: (_) async => '12345',
      )..page = page;
    }

    setUp(() {
      page = FakePage();
      events = [];
    });

    test('an activity that opens needs nothing', () async {
      final r = recovery()..start(viaKey: true);
      expect(r.busy, isTrue);
      await r.pageLoaded(target);
      expect(r.busy, isFalse);
      expect(page.loads, isEmpty);
      r.dispose();
    });

    test('a spent key falls through to the school SSO handoff', () async {
      final r = recovery()..start(viaKey: true);
      await r.pageLoaded(login);
      expect(page.loads, [std002]);
      page.answer = (kind, _) => kind == 'find' ? 'JumpTo.aspx?to=euni' : null;
      await r.pageLoaded(std002);
      final jump = Uri.parse(
        'https://ccsys.niu.edu.tw/SSO/JumpTo.aspx?to=euni',
      );
      expect(page.loads.last, jump);
      await r.pageLoaded(home);
      expect(page.loads.last, target);
      await r.pageLoaded(target);
      expect(r.busy, isFalse);
      // The link is reused while this app run lasts.
      expect(QuestionLoginRecovery.euniLink, jump);
      r.dispose();
    });

    test('without a key, cookies go first and then a new key', () async {
      final r = recovery(key: key)..start(viaKey: false);
      await r.pageLoaded(login);
      expect(page.loads, [key]);
      expect(r.step, QuestionLoginStep.autologin);
      r.dispose();
    });

    test(
      'expired SSO tries the saved account three times, then signs in again',
      () async {
        final r = recovery(
          saved: const SubmittedSchoolCredentials('b1234567', 'pw'),
        )..start(viaKey: true);
        page.answer = (kind, args) => switch (kind) {
          'capture' => 'data:image/png;base64,AAAA',
          'submit' => 'sent',
          _ => null,
        };
        await r.pageLoaded(login); // key spent
        await r.pageLoaded(ssoLogin); // school session gone
        expect(r.step, QuestionLoginStep.formLogin);
        expect(page.loads.last, login);
        for (var i = 0; i < 3; i++) {
          await r.pageLoaded(login);
        }
        expect(page.runs.where((k) => k == 'submit'), hasLength(3));
        await r.pageLoaded(login); // third answer refused too
        expect(events, ['reauthorize']);
        expect(r.step, QuestionLoginStep.refreshedSso);
        expect(page.loads.last, std002);
        await r.pageLoaded(ssoLogin);
        expect(events, ['reauthorize', 'manual']);
        expect(r.busy, isFalse);
        // A manual login that lands on home still opens the activity.
        await r.pageLoaded(home);
        expect(page.loads.last, target);
        r.dispose();
      },
    );

    test('the form fills the saved account and the code read', () async {
      final r = recovery(
        saved: const SubmittedSchoolCredentials('b1234567', 'pw'),
      )..start(viaKey: true);
      Map<String, Object?>? sent;
      page.answer = (kind, args) {
        if (kind == 'capture') return 'data:image/png;base64,AAAA';
        if (kind == 'submit') {
          sent = args;
          return 'sent';
        }
        return null;
      };
      await r.pageLoaded(login);
      await r.pageLoaded(ssoLogin);
      await r.pageLoaded(login);
      expect(sent, {
        'username': 'b1234567',
        'password': 'pw',
        'captcha': '12345',
        'image': 'data:image/png;base64,AAAA',
      });
      await r.pageLoaded(home);
      expect(page.loads.last, target);
      r.dispose();
    });

    test('no remembered account goes straight to signing in again', () async {
      final r = recovery(refreshes: false)..start(viaKey: true);
      await r.pageLoaded(login);
      await r.pageLoaded(ssoLogin);
      await r.pageLoaded(login);
      expect(events, ['reauthorize', 'manual']);
      r.dispose();
    });

    test('a stuck step times out', () async {
      QuestionLoginRecovery.euniLink = null;
      final r = QuestionLoginRecovery(
        target: target,
        autologin: () async => target,
        credentials: () async => null,
        reauthorize: () async => false,
        onManual: () => events.add('manual'),
        onTimeout: (m) => events.add(m),
        timeout: const Duration(milliseconds: 20),
      )..page = page;
      r.start(viaKey: true);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(events, ['問答載入逾時，請檢查網路後重試。']);
      expect(r.busy, isFalse);
      r.dispose();
    });

    test('school session pages are recognised as iOS does', () {
      bool expired(String u) =>
          QuestionLoginRecovery.isSchoolSessionExpired(Uri.parse(u));
      expect(expired('https://ccsys1.niu.edu.tw/SSO/login'), isTrue);
      expect(expired('https://acade.niu.edu.tw/NIU/TimeOutPage.aspx'), isTrue);
      expect(expired('https://ccsys.niu.edu.tw/SSO/Std002.aspx'), isFalse);
      expect(expired('https://ccsys.niu.edu.tw/x/Login.aspx?guid=1'), isFalse);
      expect(expired('https://euni.niu.edu.tw/login/index.php'), isFalse);
    });
  });
}
