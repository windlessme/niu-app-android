import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/features/authentication/school_login_engine.dart';

void node(String script) {
  final result = Process.runSync('node', ['-e', script]);
  expect(result.exitCode, 0, reason: result.stderr.toString());
}

void main() {
  test('fill waits for school verification, then presses 登入 once', () {
    node('''
const assert = require('node:assert/strict');
let clicks = 0;
const field = () => ({dispatchEvent(){}, checkValidity(){ return !!this.value; }});
const username = field(), password = field();
const submit = {disabled: true, click: () => clicks++};
const form = {addEventListener(){}};
global.HTMLInputElement = {prototype: {}};
Object.defineProperty(HTMLInputElement.prototype, 'value', {set(v){ this._v = v; }, get(){ return this._v; }});
Object.setPrototypeOf(username, HTMLInputElement.prototype);
Object.setPrototypeOf(password, HTMLInputElement.prototype);
global.Event = function(){};
global.window = {}; window.top = window;
global.location = {origin: 'https://ccsys1.niu.edu.tw', pathname: '/SSO/login'};
global.document = {querySelector: s => s === '#username' ? username : s === '#password' ? password
  : s === 'form.login-form' ? form : submit};
const fill = ${jsonEncode(schoolLoginFillScript('b123', 'secret'))};
assert.equal(eval(fill), 'waiting_verification');
assert.equal(clicks, 0);
submit.disabled = false;
assert.equal(eval(fill), 'submitted');
assert.equal(clicks, 1);
location.pathname = '/SSO/other';
assert.equal(eval(fill), 'blocked');
''');
  });

  test('state reports the token or a rejecting popup only', () {
    node('''
const assert = require('node:assert/strict');
let token = '', popup = null;
global.sessionStorage = {getItem: () => token};
global.getComputedStyle = () => ({visibility: 'visible'});
global.document = {querySelector: () => popup, querySelectorAll: () => []};
const state = () => JSON.parse(eval(${jsonEncode(schoolLoginStateScript)}));
assert.deepEqual(state(), {token: '', error: ''});
// "登入中…" info popup must not count as a rejection.
popup = {innerText: '登入中…', getClientRects: () => [1], getAttribute: () => 'info', querySelector: () => null};
assert.equal(state().error, '');
popup = {innerText: '帳號或密碼錯誤', getClientRects: () => [1], getAttribute: () => 'error', querySelector: () => null};
assert.equal(state().error, '帳號或密碼錯誤');
token = 'jwt';
assert.equal(state().token, 'jwt');
''');
  });

  test('school messages map to the same outcomes as iOS', () {
    expect(
      classifySchoolLoginError('帳號已被鎖定').kind,
      SchoolLoginRejection.accountLocked,
    );
    expect(
      classifySchoolLoginError('您的密碼已過期，請變更').kind,
      SchoolLoginRejection.passwordExpired,
    );
    expect(
      classifySchoolLoginError('帳號或密碼錯誤').kind,
      SchoolLoginRejection.credentials,
    );
    expect(classifySchoolLoginError('系統忙碌中').kind, SchoolLoginRejection.other);
  });
}
