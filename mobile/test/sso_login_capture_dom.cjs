// Run from mobile/: dart test/fixtures/emit_capture_script.dart | NODE_PATH=<jsdom node_modules> node test/sso_login_capture_dom.cjs
const { JSDOM } = require('jsdom');
const { readFileSync } = require('node:fs');
const assert = require('node:assert/strict');
const script = readFileSync(0, 'utf8');
const html = readFileSync('test/fixtures/sso_login.html', 'utf8');

function fixture(url = 'https://ccsys1.niu.edu.tw/SSO/login') {
  const dom = new JSDOM(html, { url, runScripts: 'outside-only' });
  const w = dom.window;
  const messages = [], listeners = {};
  const add = w.document.addEventListener.bind(w.document);
  w.document.addEventListener = (type, handler, capture) => {
    listeners[type] = handler;
    add(type, handler, capture);
  };
  w.flutter_inappwebview = { callHandler: (name, data) => messages.push({ name, data }) };
  w.eval(script);
  const get = selector => w.document.querySelector(selector);
  get('#username').value = 'b123';
  get('#password').value = 'synthetic+password';
  w.sessionStorage.setItem('niu_sso_token', 'previous-test-token');
  // jsdom cannot manufacture isTrusted browser input: call the registered
  // handler with trusted event metadata, while using actual DOM selectors.
  const fire = (type, selector, extra = {}) => listeners[type]?.({
    type, target: get(selector), isTrusted: true, ...extra,
    preventDefault() { throw Error('capture must not change default handling'); },
    stopPropagation() { throw Error('capture must not stop school handlers'); },
  });
  return { w, messages, get, fire };
}

const f = fixture();
f.fire('click', '#login-label');
f.fire('keydown', '#password', { key: 'Enter' });
f.fire('submit', 'form');
assert.equal(f.messages.length, 0, 'disabled challenge button must block capture');
f.get('.btn-login').disabled = false; // Fixture state only; no CAPTCHA is loaded.
f.fire('click', '#login-label');
f.fire('submit', 'form');
f.fire('keydown', '#password', { key: 'Enter' });
assert.equal(f.messages.length, 3);
assert.deepEqual(JSON.parse(JSON.stringify(f.messages[0])), {
  name: 'schoolLoginSubmitted', data: {
    capability: 'fixture-capability', account: 'b123', password: 'synthetic+password',
    previousToken: 'previous-test-token',
  },
});
f.get('#password').type = 'text';
f.get('.btn-login').type = 'button';
f.fire('click', '#login-label');
assert.equal(f.messages.length, 4, 'show-password and click-only variant supported');
f.fire('click', '#show-password');
f.fire('keydown', '#cert-pin', { key: 'Enter' });
f.fire('keydown', '#fido2-account', { key: 'Enter' });
for (const extra of [{ key: 'x' }, { key: 'Enter', isComposing: true },
  { key: 'Enter', repeat: true }, { key: 'Enter', ctrlKey: true }]) {
  f.fire('keydown', '#password', extra);
}
for (const [type, selector] of [['click', '#login-label'], ['submit', 'form'], ['keydown', '#password']]) {
  f.fire(type, selector, { isTrusted: false, key: 'Enter' });
}
assert.equal(f.messages.length, 4, 'unrelated and synthetic events ignored');
f.get('#password').dispatchEvent(new f.w.KeyboardEvent('keydown', { key: 'Enter', bubbles: true }));
assert.equal(f.messages.length, 4, 'real DOM synthetic event rejected');
for (const url of ['https://evil.test/SSO/login', 'https://ccsys1.niu.edu.tw/SSO/force-change-password']) {
  const other = fixture(url);
  other.get('.btn-login').disabled = false;
  other.fire('click', '#login-label');
  assert.equal(other.messages.length, 0);
}
console.log('SSO capture DOM fixture assertions passed (trusted metadata simulated; no login/network requests).');
