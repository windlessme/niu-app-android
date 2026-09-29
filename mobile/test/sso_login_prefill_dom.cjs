// dart test/fixtures/emit_prefill_script.dart | NODE_PATH=<jsdom node_modules> node test/sso_login_prefill_dom.cjs
const { JSDOM } = require('jsdom');
const { readFileSync } = require('node:fs');
const assert = require('node:assert/strict');
const script = readFileSync(0, 'utf8');
const html = readFileSync('test/fixtures/sso_login.html', 'utf8');
function fixture(url = 'https://ccsys1.niu.edu.tw/SSO/login') {
  const w = new JSDOM(html, {url, runScripts: 'outside-only'}).window;
  const get = selector => w.document.querySelector(selector);
  return {w, get};
}
const {w, get} = fixture();
const events = [];
for (const id of ['username', 'password']) {
  for (const event of ['input', 'change']) {
    get('#' + id).addEventListener(event, () => events.push(id + ':' + event));
  }
}
w.document.addEventListener('submit', () => { throw Error('must not submit'); });
const buttonDisabled = get('.btn-login').disabled;
assert.equal(w.eval(script), 'done');
assert.equal(get('#username').value, 'b123');
// Password inputs strip line breaks through the browser's native value setter.
assert.equal(get('#password').value, '";window.injected=true;//</script>密碼\\');
assert.equal(w.injected, undefined);
assert.deepEqual(events, ['username:input', 'username:change', 'password:input', 'password:change']);
assert.equal(get('.btn-login').disabled, buttonDisabled);
assert.equal(w.localStorage.length + w.sessionStorage.length, 0);
get('#password').value = 'edited';
w.eval(script);
assert.equal(get('#password').value, 'edited');
for (const url of ['http://ccsys1.niu.edu.tw/SSO/login', 'https://evil.test/SSO/login',
  'https://ccsys1.niu.edu.tw/SSO/other', 'https://ccsys1.niu.edu.tw/SSO/login/',
  'https://ccsys1.niu.edu.tw:444/SSO/login']) {
  const f = fixture(url);
  assert.equal(f.w.eval(script), 'blocked');
  assert.equal(f.get('#password').value, '');
}
const edited = fixture();
edited.get('#username').value = 'manual';
edited.w.eval(script);
assert.equal(edited.get('#password').value, '');
const cleared = fixture();
cleared.w.__niuLoginEdited = true;
cleared.w.eval(script);
assert.equal(cleared.get('#username').value, '');
const waiting = fixture();
waiting.get('form').remove();
assert.equal(waiting.w.eval(script), 'waiting');
const framed = fixture();
const iframe = framed.w.document.createElement('iframe');
framed.w.document.body.appendChild(iframe);
iframe.contentDocument.body.innerHTML = html;
assert.equal(iframe.contentWindow.eval(script), 'blocked');
assert.equal(iframe.contentDocument.querySelector('#password').value, '');
console.log('SSO prefill DOM assertions passed.');
