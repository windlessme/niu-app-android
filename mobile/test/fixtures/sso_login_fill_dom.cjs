// dart test/fixtures/emit_login_fill_script.dart | NODE_PATH=<jsdom node_modules> node test/fixtures/sso_login_fill_dom.cjs
const { JSDOM } = require('jsdom');
const { readFileSync } = require('node:fs');
const assert = require('node:assert/strict');
const script = readFileSync(0, 'utf8');
const html = readFileSync('test/fixtures/sso_login.html', 'utf8');
const w = new JSDOM(html, { url: 'https://ccsys1.niu.edu.tw/SSO/login', runScripts: 'outside-only' }).window;
const q = s => w.document.querySelector(s);
const events = [];
for (const id of ['username', 'password'])
  for (const e of ['input', 'change']) q('#' + id).addEventListener(e, () => events.push(id + ':' + e));
let clicks = 0;
q('.btn-login').addEventListener('click', () => clicks++);
// The fixture's button is disabled until Turnstile issues a token.
assert.equal(w.eval(script), 'waiting_verification');
assert.equal(q('#username').value, 'b123');
assert.equal(w.injected, undefined);
assert.deepEqual(events, ['username:input', 'username:change', 'password:input', 'password:change']);
assert.equal(clicks, 0);
q('.btn-login').disabled = false;
assert.equal(w.eval(script), 'submitted');
assert.equal(clicks, 1);
const other = new JSDOM(html, { url: 'https://evil.test/SSO/login', runScripts: 'outside-only' }).window;
assert.equal(other.eval(script), 'blocked');
console.log('ok');
