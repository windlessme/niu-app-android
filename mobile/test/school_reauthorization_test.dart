import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/features/authentication/school_reauthorization.dart';

void main() {
  test(
    'automatic submission is single shot and yields to school challenges',
    () {
      final result = Process.runSync('node', [
        '-e',
        '''
const assert = require('node:assert/strict');
const script = ${jsonEncode(schoolAutomaticSubmitScript)};
let challenge = null, clicks = 0;
const button = {disabled: true, click: () => clicks++};
const form = {querySelector: s => s.startsWith('app-turnstile') ? challenge : s.startsWith('button') ? button : {value: 'fixture'}};
global.window = {}; window.top = window;
global.location = {origin:'https://ccsys1.niu.edu.tw', pathname:'/SSO/login'};
global.document = {querySelector: () => form};
assert.equal(eval(script), 'waiting');
button.disabled = false;
challenge = {};
assert.equal(eval(script), 'interaction-required');
assert.equal(clicks, 0);
challenge = null;
assert.equal(eval(script), 'submitted');
assert.equal(eval(script), 'submitted');
assert.equal(clicks, 1);
location.origin = 'https://example.com';
assert.equal(eval(script), 'blocked');
assert.equal(clicks, 1);
''',
      ]);
      expect(result.exitCode, 0, reason: result.stderr.toString());
    },
  );
}
