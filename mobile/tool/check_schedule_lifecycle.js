// First-login/ASP.NET fixtures; executes the shipped query state machine.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const source = fs.readFileSync(path.join(__dirname, '../lib/features/schedule/schedule_screen.dart'), 'utf8');
const script = source.match(/const scheduleQueryScript = r'''([\s\S]*?)''';/)[1];
const storage = new Map();
let clicks = 0;
function frame(rows, options = {}) {
  const table = {
    innerText: '節次 星期一', innerHTML: JSON.stringify(rows),
    querySelectorAll: () => rows.map(row => ({querySelectorAll: () => row.map(innerText => ({innerText}))})),
  };
  const button = {disabled: false, click: () => { clicks++; options.click?.(); }};
  const listeners = {};
  const w = {
    __niuAcademicRun: 'first-login', frames: [],
    document: {
      readyState: 'complete', location: {href: 'https://acade.niu.edu.tw/NIU/Application/TKE/TKE22/TKE2240_01.aspx'},
      querySelector: () => button, getElementById: () => table,
    },
    sessionStorage: {
      getItem: key => storage.get(key) || null,
      setItem: (key, value) => storage.set(key, value), removeItem: key => storage.delete(key),
    },
    addEventListener: (name, cb) => { listeners[name] = cb; },
  };
  return {w, rows, table, button, listeners};
}
const header = ['節次', '星期一'];
const first = frame([header]);
const inaccessible = {};
Object.defineProperty(inaccessible, 'document', {get() { throw new Error('cross-origin'); }});
const root = {document: {location: {href: 'about:blank'}}, frames: [inaccessible, first.w]};
const read = () => vm.runInNewContext(script, {window: root, URL});
first.w.document.readyState = 'loading';
assert.equal(read(), false);
assert.equal(clicks, 0);
first.w.document.readyState = 'complete';
first.button.disabled = true;
assert.equal(read(), false);
first.button.disabled = false;
assert.equal(read(), false); // query begins, header is not a result
for (let i = 0; i < 10; i++) assert.equal(read(), false);
assert.equal(clicks, 1); // old document still visible while POST is pending
first.listeners.beforeunload();
assert.equal(read(), false);
const response = frame([header]);
root.frames[1] = response.w; // no top-level onLoadStop
response.w.document.readyState = 'loading';
assert.equal(read(), false);
response.w.document.readyState = 'complete';
assert.equal(read(), false); // first settled DOM observation
response.rows.push(['1', '數學']); // partial response changes between reads
assert.equal(read(), false);
assert.equal(read(), true);
assert.equal(clicks, 1); // replacement response must not POST again
root.frames[1] = first.w;
assert.equal(read(), false); // stale old document is never eligible

// Refresh must not reuse a previous attempt's postback receipt.
const refresh = frame([header]);
refresh.w.__niuAcademicRun = 'refresh';
root.frames[1] = refresh.w;
assert.equal(read(), false);
assert.equal(clicks, 2);
const emptyResponse = frame([header]);
emptyResponse.w.__niuAcademicRun = 'refresh';
root.frames[1] = emptyResponse.w;
assert.equal(read(), false);
assert.equal(read(), true); // confirmed, settled header-only empty timetable
assert.equal(clicks, 2);

// UpdatePanel: request lifecycle, including a still-present old timetable.
let busy = false, endRequest;
const ajax = frame([header, ['1', '']], {click: () => { busy = true; }});
ajax.w.__niuAcademicRun = 'ajax';
ajax.w.Sys = {WebForms: {PageRequestManager: {getInstance: () => ({
  get_isInAsyncPostBack: () => busy, add_endRequest: cb => { endRequest = cb; },
})}}};
root.frames[1] = ajax.w;
assert.equal(read(), false);
assert.equal(read(), false);
ajax.rows[1][1] = '英文';
assert.equal(read(), false);
busy = false;
endRequest();
assert.equal(read(), false);
assert.equal(read(), true);
assert.equal(clicks, 3);
console.log('PASS: first-login frames, pending postback, partial DOM, stale document, refresh, empty response, UpdatePanel');
