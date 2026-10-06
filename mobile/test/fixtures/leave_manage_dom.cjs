// Runs the shipped 學生請假修改 scripts and the leave runtime's modify/supplement
// guards against a hand-built copy of the school's frames.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const s = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));

// ── 學生請假修改 list (SEC2015_01) inside MainFrame's mainFrame ──────────────
const clicks = [], timers = [];
function cell(text, onclick) {
  return {innerText: text, getAttribute: n => n === 'onclick' ? onclick || null : null,
    click: () => clicks.push(text + ':' + onclick)};
}
function row(no, {del, mod, detail}) {
  const cells = [cell(no), cell('事假', mod ? `doEdit1_2('${no}','Mod')` : null),
    cell('115/10/08', detail ? `doEdit1_2('${no}','Detail')` : null)];
  const link = del ? {getAttribute: n => n === 'href' ? `javascript:__doPostBack('DataGrid$ctl0${del}$del','')` : null} : null;
  return {cells, querySelector: sel => sel === 'th' ? null : sel.startsWith('a[id') ? link : null};
}
const header = {cells: [cell('假單序號'), cell('請假類別'), cell('請假起日')], querySelector: sel => sel === 'th' ? {} : null};
let deleteAnswer = true, async = false;
function listDoc(rows) {
  const grid = {rows: [header, ...rows]};
  const view = {Sys: {WebForms: {PageRequestManager: {getInstance: () => ({get_isInAsyncPostBack: () => async})}}},
    doDelete: () => deleteAnswer, setTimeout: f => timers.push(f)};
  const d = {location: {href: 'https://acade.niu.edu.tw/NIU/Application/SEC/SEC20/SEC2015_01.aspx'}, readyState: 'complete',
    body: {innerText: '【第 頁/共 頁】'}, defaultView: view, querySelector: () => null,
    getElementById: id => id === 'DataGrid' ? grid : id === 'QUERY_BTN1' ? {disabled: false, click: () => clicks.push('QUERY')} : null};
  return {d, grid};
}
const blank = {location: {href: 'https://acade.niu.edu.tw/NIU/blank.aspx'}};
const mainWin = {document: blank, frames: {length: 0}, location: {set href(v) { clicks.push('NAV:' + v); }}};
const top = {document: {location: {href: 'https://acade.niu.edu.tw/NIU/MainFrame.aspx'}}, frames: {length: 1, 0: mainWin, mainFrame: mainWin},
  hideView: () => clicks.push('HIDE')};
const context = vm.createContext({window: top, URL, JSON, Date, Array, String, Math});
const run = source => vm.runInContext(source, context);

assert.equal(run(s.navigation), null);
assert.ok(clicks.includes('NAV:/NIU/Application/SEC/SEC20/SEC2015_.aspx?progcd=SEC2015'));
assert.equal(run(s.navigation), null); // Opened once only.
assert.equal(clicks.filter(c => c.startsWith('NAV:')).length, 1);

const first = listDoc([row('D1', {del: 2, mod: true}), row('D2', {detail: true}), row('D3', {})]);
mainWin.document = first.d;
assert.equal(run(s.navigation), null);
assert.ok(clicks.includes('QUERY'));
assert.equal(run(s.navigation), null); // Pager still unsettled.
first.d.body.innerText = '【第 1 頁/共 1 頁】';
async = true;
assert.equal(run(s.navigation), null);
async = false;
assert.equal(run(s.navigation), 'ready');
assert.equal(clicks.filter(c => c === 'QUERY').length, 1);

const actions = JSON.parse(run(s.extract)).actions;
assert.deepEqual(actions, [
  {formNo: 'D1', withdraw: true, modify: true, supplement: false},
  {formNo: 'D2', withdraw: false, modify: false, supplement: true},
]);

assert.equal(run(s.openMissing), 'missing');
assert.equal(run(s.openD2Detail), 'opened');
assert.equal(run(s.openD2Detail), 'opened');
assert.equal(clicks.filter(c => c.includes("'Detail'")).length, 1);

// 撤回: confirm and postback run from timers, never inside the call.
assert.equal(run(s.state), 'none');
assert.equal(run(s.withdrawD2), 'missing'); // D2 has no delete link.
assert.equal(run(s.withdrawD1), 'scheduled');
assert.equal(run(s.withdrawD1), 'changed'); // One withdraw per page.
assert.equal(run(s.state), 'confirming');
assert.equal(timers.length, 1);
timers.shift()();
assert.equal(run(s.state), 'waiting');
assert.equal(timers.length, 1);
assert.equal(timers[0], "__doPostBack('DataGrid$ctl02$del','')");
first.grid.rows.splice(1, 1); // The grid re-renders without D1.
assert.equal(run(s.state), 'removed');

// The check reads a new page, never the replaced one.
assert.equal(run(s.reset), true);
assert.equal(run(s.listedD1), null);
assert.equal(run(s.state), 'none');
const second = listDoc([row('D2', {detail: true})]);
mainWin.document = second.d;
run(s.navigation);
second.d.body.innerText = '【第 1 頁/共 1 頁】';
assert.equal(run(s.navigation), 'ready');
assert.equal(run(s.listedD1), 'gone');

// A declined school confirm sends nothing.
const third = listDoc([row('D1', {del: 3, mod: true})]);
run(s.reset); mainWin.document = third.d; run(s.navigation);
third.d.body.innerText = '【第 1 頁/共 1 頁】';
assert.equal(run(s.navigation), 'ready');
deleteAnswer = false;
timers.length = 0;
assert.equal(run(s.withdrawD1), 'scheduled');
timers.shift()();
assert.equal(run(s.state), 'declined');
assert.equal(timers.length, 0);

top.frames = {length: 2, 0: mainWin, mainFrame: mainWin,
  1: {document: {location: {href: 'https://acade.niu.edu.tw/NIU/TimeoutPage.aspx'}}, frames: {length: 0}}};
assert.equal(run(s.navigation), 'session-expired');

// ── The leave form opened from that list: only this form, in this mode ─────
const fields = {
  M_STNO: {textContent: 'B123'}, M_FORM_NO: {value: 'D1'}, Mode: {value: 'MOD'},
  M_HOLIDAY_CODE: {value: '023', disabled: false, options: [{value: '023', text: '事假'}], selectedOptions: [{text: '事假'}]},
  M_HOLIDAY_DATE_S: {value: '115/10/01'}, M_HOLIDAY_DATE_E: {value: '115/10/01'},
  M_APP_ORIGIN: {value: 'fixture', maxLength: 1000}, CheckBox1: {checked: false, disabled: false},
  SEND_BTN1: {value: '修改', disabled: false, click: () => clicks.push('SUBMIT')},
};
let endRequests = [];
const manager = {get_isInAsyncPostBack: () => false, add_endRequest: cb => endRequests.push(cb)};
fields.SEND_BTN1.form = {action: 'https://acade.niu.edu.tw/NIU/Application/SEC/SEC20/SEC2010_01.aspx', method: 'post'};
const formDoc = {location: {href: 'https://acade.niu.edu.tw/NIU/Application/SEC/SEC20/SEC2010_01.aspx'}, readyState: 'complete',
  getElementById: id => fields[id], querySelectorAll: () => [], body: {innerText: 'form'}};
const formWin = {document: formDoc, frames: [], Sys: {WebForms: {PageRequestManager: {getInstance: () => manager}}}, setTimeout: f => f()};
formDoc.defaultView = formWin;
const form = vm.createContext({window: formWin, document: formDoc, URL, URLSearchParams, Uint8Array, JSON, Math, run: 'fixture', op: '', args: {}});
const execute = (op, args = {}) => {
  form.op = op; form.args = {owner: 'b123', ...args};
  const r = vm.runInContext('(()=>{' + s.runtime + '})()', form);
  return r == null ? null : JSON.parse(r);
};
const mod = {formNo: 'D1', mode: 'MOD'};
// A new application never reads an existing form; another form number neither.
assert.equal(execute('read'), null);
assert.equal(execute('read', {formNo: 'D2', mode: 'MOD'}), null);
assert.equal(execute('read', {formNo: 'D1', mode: 'DETAIL'}), null);
const page = execute('read', mod);
assert.equal(page.formNo, 'D1');
assert.equal(page.mode, 'MOD');
assert.equal(page.editable, true);
assert.equal(page.submitLabel, '修改');
// MOD submits through the school's「修改」button and reports that it was handled.
assert.ok(execute('submit', {...mod, revision: page.revision, expected: page}).ok);
assert.ok(clicks.includes('SUBMIT'));
assert.equal(execute('submissionResult', mod), null);
endRequests.forEach(cb => cb());
assert.deepEqual(execute('submissionResult', mod), {sent: true});

// DETAIL (補檔): fields are locked; only attachments and「送出」.
formWin.__niuPersonalLeave = undefined; // A new screen starts a new run.
const form2 = vm.createContext({window: formWin, document: formDoc, URL, URLSearchParams, Uint8Array, JSON, Math, run: 'fixture', op: '', args: {}});
fields.Mode.value = 'DETAIL'; fields.SEND_BTN1.value = '送出'; fields.M_HOLIDAY_CODE.disabled = true;
formDoc.__niuLeaveRevision = undefined;
const detailRun = (op, args = {}) => {
  form2.op = op; form2.args = {owner: 'b123', formNo: 'D1', mode: 'DETAIL', ...args};
  const r = vm.runInContext('(()=>{' + s.runtime + '})()', form2);
  return r == null ? null : JSON.parse(r);
};
const locked = detailRun('read');
assert.equal(locked.editable, false);
for (const op of ['type', 'date', 'openPeriods', 'applyPeriods', 'draft']) {
  assert.equal(detailRun(op, {revision: locked.revision}).error, '補交證明文件只能附加檔案');
}
fields.SEND_BTN1.value = '修改';
assert.equal(detailRun('submit', {revision: locked.revision, expected: locked}).error, '校方未開放送出');
fields.SEND_BTN1.value = '送出';
assert.ok(detailRun('submit', {revision: locked.revision, expected: locked}).ok);
console.log('leave manage fixtures passed');
