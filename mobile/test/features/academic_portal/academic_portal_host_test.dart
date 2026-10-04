import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/features/academic_portal/academic_portal_screen.dart';
import 'package:niu_mobile/features/academic_portal/academic_portal_scripts.dart';

void main() {
  testWidgets('platform host fills body and timeout remains visible', (
    tester,
  ) async {
    const host = Key('platform-host');
    await tester.pumpWidget(
      MaterialApp(
        home: AcademicPortalScreen(
          title: '課表',
          bridge: false,
          target: Uri.parse('https://acade.niu.edu.tw/NIU/test.aspx'),
          extractScript: 'null',
          loadTimeout: const Duration(seconds: 2),
          webViewBuilder: (_) => const SizedBox(key: host),
        ),
      ),
    );
    await tester.pump();
    final size = tester.getSize(find.byKey(host));
    expect(size.width, greaterThan(100));
    expect(size.height, greaterThan(100));
    expect(find.text('正在向學校系統讀取資料'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('學校系統回應逾時。可以再試一次，或直接開啟學校網頁。'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  test('navigation waits for GUID redirect and discovers settled frames', () {
    final script = academicNavigationScript(
      Uri.parse('https://acade.niu.edu.tw/NIU/target.aspx'),
    );
    final result = Process.runSync('node', [
      '-e',
      '''
const assert = require('node:assert/strict');
const script = ${jsonEncode(script)};
function doc(url, href) { return {location: {href: url}, readyState: 'complete', getElementById: () => href ? {getAttribute: () => href} : null}; }
global.window = {document: doc('https://acade.niu.edu.tw/NIU/Login.aspx?GUID=token'), frames: []};
assert.equal(eval(script), null);
window.document = doc('about:blank');
assert.equal(eval(script), null);
window.document = doc('https://ccsys.niu.edu.tw/SSO/Std002.aspx', './bridge.aspx');
assert.equal(eval(script), 'https://ccsys.niu.edu.tw/SSO/bridge.aspx');
window.document = doc('https://acade.niu.edu.tw/NIU/MainFrame.aspx');
window.document.readyState = 'loading';
assert.equal(eval(script), null);
window.document.readyState = 'interactive';
assert.equal(eval(script), 'https://acade.niu.edu.tw/NIU/target.aspx');
window.document.readyState = 'complete';
assert.equal(eval(script), 'https://acade.niu.edu.tw/NIU/target.aspx');
window.frames = [{document: doc('https://acade.niu.edu.tw/NIU/target.aspx'), frames: []}];
assert.equal(eval(script), 'ready');
window.document = doc('about:blank');
window.frames[0].document.readyState = 'loading';
assert.equal(eval(script), null);
window.frames[0].document.readyState = 'complete';
assert.equal(eval(script), 'ready');
window.frames = [];
window.document = doc('https://acade.niu.edu.tw/NIU/Login.aspx');
assert.equal(eval(script), 'session-expired');
window.document = doc('https://acade.niu.edu.tw/NIU/MainFrame.aspx');
window.frames = [{document: doc('https://acade.niu.edu.tw/NIU/TimeOutPage.aspx'), frames: []}];
assert.equal(eval(script), 'session-expired');
''',
    ]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
  });

  test(
    'read envelope rejects replaced frames and gates pending preparation',
    () {
      final read = academicReadScript(
        extract: 'JSON.stringify([1])',
        prepare: 'window.ready',
        run: 'attempt-1',
      );
      final identity = academicDocumentIdentityScript('attempt-1');
      final result = Process.runSync('node', [
        '-e',
        '''
const assert = require('node:assert/strict');
const doc = () => ({location: {href: 'https://acade.niu.edu.tw/target'}, readyState: 'complete'});
global.window = {document: doc(), frames: [{document: doc(), frames: []}], ready: false};
const read = ${jsonEncode(read)}, identity = ${jsonEncode(identity)};
assert.equal(eval(read), null);
window.ready = true;
const result = JSON.parse(eval(read));
assert.equal(result.value, '[1]');
assert.equal(result.signature, eval(identity));
window.frames[0].document = doc();
assert.notEqual(result.signature, eval(identity));
window.frames[0].document.readyState = 'loading';
assert.notEqual(result.signature, eval(identity));
''',
      ]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
    },
  );

  test('frame wakeup runs before unrelated resources finish loading', () {
    final result = Process.runSync('node', [
      '-e',
      '''
const assert = require('node:assert/strict');
let calls = 0;
const events = {};
global.location = {hostname: 'acade.niu.edu.tw'};
global.document = {readyState: 'loading', addEventListener: (name, cb) => {events[name] = cb;}};
global.window = {addEventListener: (name, cb) => {events[name] = cb;}};
$academicNavigationWakeupScript
document.readyState = 'interactive';
events.readystatechange();
assert.equal(calls, 0);
window.flutter_inappwebview = {callHandler: (name, ...args) => {
  assert.equal(name, 'academicSnapshot'); assert.equal(args.length, 0); calls++;
}};
events.flutterInAppWebViewPlatformReady();
assert.equal(calls, 1);
document.readyState = 'complete';
events.readystatechange();
assert.equal(calls, 2);
''',
    ]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
  });

  test('visible challenges are exposed while hidden tokens are ignored', () {
    final result = Process.runSync('node', [
      '-e',
      '''
const assert = require('node:assert/strict');
const script = ${jsonEncode(portalInteractionScript)};
let controls = [];
const doc = {location: {href: 'https://acade.niu.edu.tw/NIU/Login.aspx?GUID=fixture'}, querySelectorAll: () => controls};
global.window = {document: doc, frames: [], innerWidth: 400, innerHeight: 700, getComputedStyle: () => ({visibility: 'visible'})};
assert.equal(eval(script), null);
controls = [{type: 'hidden', getClientRects: () => [1]}];
assert.equal(eval(script), null);
controls = [{type: 'text', getClientRects: () => []}];
assert.equal(eval(script), null);
controls = [{type: 'text', getClientRects: () => [1]}];
assert.equal(eval(script), 'interaction-required');
window.getComputedStyle = () => ({visibility: 'hidden'});
assert.equal(eval(script), null);
window.getComputedStyle = () => ({visibility: 'visible'});
const child = {...window};
window = {document: {location: {href: 'about:blank'}}, frames: [child], innerWidth: 400, innerHeight: 700};
assert.equal(eval(script), 'interaction-required');
// acade keeps its timeout login (a password box) in a zero-height frame.
child.innerHeight = 0;
assert.equal(eval(script), null);
child.innerHeight = 700;
window.innerWidth = 0;
assert.equal(eval(script), null);
window.innerWidth = 400;
doc.location.href = 'https://example.com/';
assert.equal(eval(script), null);
''',
    ]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
  });

  test('menu polling opens a delayed submenu without repeating mutations', () {
    final script = academicMenuScript('歷年成績');
    final result = Process.runSync('node', [
      '-e',
      '''
const assert = require('node:assert/strict');
const script = ${jsonEncode(script)};
let clicks = 0;
const parent = {textContent: '成績查詢作業', dataset: {}, click: () => clicks++};
const child = {textContent: '歷年成績', dataset: {}, click: () => clicks++};
const links = [parent];
global.window = {document: {querySelectorAll: () => links}, frames: []};
assert.equal(eval(script), false);
assert.equal(eval(script), false);
assert.equal(clicks, 1);
links.push(child);
assert.equal(eval(script), true);
eval(script);
assert.equal(clicks, 2);
''',
    ]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
  });
}
