// Runs the shipped 活動報名 list script against hand-built rows whose
// 活動編號 paragraph also carries status and 認證 badges.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const s = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));

// A paragraph made of text and badge pieces; cloneNode copies the pieces.
function paragraph(row, pieces, modal = false) {
  const p = {
    pieces: [...pieces],
    closest: sel => sel === '.modal' ? (modal ? {} : null) : sel === '.enr-list-sec' ? row : null,
    cloneNode: () => paragraph(row, p.pieces, modal),
    querySelectorAll: sel => sel === '.badge'
      ? p.pieces.filter(x => x.badge).map(x => ({remove: () => p.pieces.splice(p.pieces.indexOf(x), 1)})) : [],
    get textContent() { return p.pieces.map(x => x.text).join(''); },
    get innerText() { return p.textContent; },
  };
  return p;
}
const badge = text => ({text, badge: true});
function eventRow(name, pieces, {link = '', modalFirst = false} = {}) {
  const row = {};
  const paragraphs = [];
  if (modalFirst) paragraphs.push(paragraph(row, [{text: '活動編號：999'}], true));
  paragraphs.push(paragraph(row, pieces));
  Object.assign(row, {
    querySelector: sel => sel === 'h3' ? {innerText: name}
      : sel.startsWith('a[href') && link ? {href: link} : null,
    querySelectorAll: sel => sel === 'p' ? paragraphs : [],
  });
  return row;
}
const rows = [
  eventRow('徽章', [{text: '活動編號：12345'}, badge('報名中'), {text: '\n '}, badge('專業進取 (已認證)')]),
  eventRow('英數徽章', [{text: '活動編號：678'}, badge('A1')]),
  eventRow('彈窗在前', [{text: '活動編號： ４２ '}], {modalFirst: true}),
  eventRow('看不懂編號', [{text: '活動編號：待公告'}], {link: 'https://ccsys.niu.edu.tw/MvcTeam/Act/Apply/777'}),
  eventRow('沒有編號', [{text: '主辦單位：學務處'}]),
];
const container = {querySelectorAll: sel => sel === '.row.enr-list-sec' ? rows : []};
const document = {
  querySelector: sel => sel.startsWith('.col-md-11') ? container : null,
  querySelectorAll: () => [],
};
const context = vm.createContext({document, JSON, Array, Set, String});
const events = JSON.parse(vm.runInContext(s.list, context));
assert.deepEqual(events.map(e => [e.name, e.id]), [
  ['徽章', '12345'],
  ['英數徽章', '678'],
  ['彈窗在前', '42'],
  ['看不懂編號', '777'],
  ['沒有編號', ''],
]);
