import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart' as web;
import 'package:html/parser.dart' as html;
import 'package:niu_mobile/core/web/event_cookie_store.dart';
import 'package:niu_mobile/core/session/campus_session.dart';
import 'package:niu_mobile/features/events/event_login_service.dart';
import 'package:niu_mobile/features/events/event_portal.dart';
import 'package:niu_mobile/features/events/events_screen.dart';
import '../../support/fakes.dart';

void node(String source) {
  final result = Process.runSync('node', ['-e', source]);
  expect(result.exitCode, 0, reason: result.stderr.toString());
}

void main() {
  test('event IDs leave status badges out and accept digits only', () {
    final dir = Directory.systemTemp.createTempSync('events_list');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/scripts.json')
      ..writeAsStringSync(jsonEncode({'list': eventsExtractScript}));
    final result = Process.runSync('node', [
      'test/fixtures/events_list_dom.cjs',
      file.path,
    ]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  });

  test(
    'restored event entry goes directly to the requested protected page',
    () async {
      final session = CampusSession(vault: MemoryVault())..account = 'b123';
      expect(
        await eventPortalEntry(session, target: eventVerificationUri),
        eventVerificationUri,
      );
      final action = Uri.parse(
        'https://ccsys.niu.edu.tw/MvcTeam/Act/Apply/fixture',
      );
      expect(await eventPortalEntry(session, target: action), action);
      await expectLater(
        eventPortalEntry(session, target: Uri.parse('https://example.com/')),
        throwsArgumentError,
      );
      session.dispose();
    },
  );

  test(
    'public form contract preserves CSRF, encoding and protected return URL',
    () {
      final document = html.parse(
        File('test/fixtures/event_login.html').readAsStringSync(),
      );
      final form = document.querySelector('#loginForm form')!;
      final inputs = {
        for (final input in form.querySelectorAll('input[name]'))
          input.attributes['name']!: input.attributes,
      };
      const password = 'quotes\'"\\\n密碼&=<>𝄞';
      node('''
const assert = require('node:assert/strict');
const inputs = ${jsonEncode(inputs)};
const script = ${jsonEncode(eventLoginFormScript('student', password))};
global.location = {href: ${jsonEncode(eventLoginUri.toString())}};
let submitted = 0;
const form = {
  action: ${jsonEncode(form.attributes['action'])},
  method: ${jsonEncode(form.attributes['method'])},
  querySelector(selector) {
    if (selector.startsWith('.cf-turnstile')) return null;
    const name = selector.match(/name="([^"]+)"/)[1];
    const input = inputs[name];
    const type = selector.match(/type="([^"]+)"/);
    return input && (!type || input.type === type[1]) ? input : null;
  }
};
global.document = {querySelector: selector => selector === '#loginForm form' ? form : null};
global.HTMLFormElement = {prototype: {submit() { assert.equal(this, form); submitted++; }}};
assert.equal(eval(script), 'submitted');
assert.equal(submitted, 1);
assert.equal(inputs.Account.value, 'student');
assert.equal(inputs.Password.value, ${jsonEncode(password)});
assert.equal(inputs.__RequestVerificationToken.value, 'fixture-csrf');
assert.equal(new URL(form.action).searchParams.get('ReturnUrl'), '/MvcTeam/Act/ApplyMe');
form.action = 'https://evil.test/MvcTeam/Account/Login';
assert.equal(eval(script), 'wrong-action');
form.action = '/MvcTeam/Act/Apply/123';
assert.equal(eval(script), 'wrong-action');
form.action = '/MvcTeam/Account/Login';
inputs.__RequestVerificationToken.value = '';
assert.equal(eval(script), 'missing-fields');
location.href = 'https://ccsys.niu.edu.tw/MvcTeam/Act/Apply/123';
assert.equal(eval(script), 'wrong-page');
assert.equal(submitted, 1);
''');
    },
  );

  test(
    'navigation reconnects expired sessions and preserves selected target',
    () {
      final script = eventNavigationScript(eventVerificationUri);
      final detail = eventNavigationScript(
        Uri.parse('https://ccsys.niu.edu.tw/MvcTeam/Act/Apply/fixture'),
      );
      node('''
const assert = require('node:assert/strict');
const script = ${jsonEncode(script)};
const detail = ${jsonEncode(detail)};
global.document = {readyState: 'complete', body: {innerText: '活動列表'}, querySelector: () => null};
global.location = {href: 'https://ccsys.niu.edu.tw/MvcTeam/Account/Login?GUID=old-speculation'};
document.location = location;
document.querySelectorAll = () => [];
global.window = {document, frames: []};
assert.equal(eval(script), 'login-required');
location.href = 'https://ccsys.niu.edu.tw/MvcTeam/Act';
assert.equal(eval(script), 'https://ccsys.niu.edu.tw/MvcTeam/Act/ApplyMe');
assert.equal(eval(detail), 'https://ccsys.niu.edu.tw/MvcTeam/Act/Apply/fixture');
document.querySelector = () => ({});
assert.equal(eval(script), 'login-required');
document.querySelector = () => null;
location.href = 'https://ccsys.niu.edu.tw/MvcTeam/Act/ApplyMe';
assert.equal(eval(script), 'ready');
document.body.innerText = '';
assert.equal(eval(script), null);
''');
      expect(detail, isNot(contains('.submit(')));
      expect(detail, isNot(contains('.click(')));
    },
  );

  test(
    'public list and failed/login responses cannot verify an event session',
    () {
      node('''
const assert = require('node:assert/strict');
const script = ${jsonEncode(eventSessionVerifiedScript)};
global.location = {href: 'https://ccsys.niu.edu.tw/MvcTeam/Act'};
global.document = {readyState: 'complete', body: {innerText: '沒有報名紀錄'}, querySelector: s => s === '.container.body-content' ? {} : null};
assert.equal(eval(script), false);
location.href += '/ApplyMe';
assert.equal(eval(script), true);
document.querySelector = () => ({});
assert.equal(eval(script), false);
document.querySelector = () => null;
assert.equal(eval(script), false);
''');
    },
  );

  test(
    'cookie restoration rejects unrelated domains, paths and expired cookies',
    () {
      expect(usableEventCookie(web.Cookie(name: 'auth', value: 'v')), isTrue);
      for (final cookie in [
        web.Cookie(name: 'auth', value: 'v', domain: '.niu.edu.tw'),
        web.Cookie(name: 'auth', value: 'v', domain: 'evil.test'),
        web.Cookie(name: 'auth', value: 'v', path: '/SSO'),
        web.Cookie(name: 'auth', value: 'v', expiresDate: 1),
      ]) {
        expect(usableEventCookie(cookie), isFalse);
      }
      expect(
        isEventUri(
          Uri.parse('https://ccsys.niu.edu.tw.evil.test/MvcTeam/Account/Login'),
        ),
        isFalse,
      );
    },
  );
}
