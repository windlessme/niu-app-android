// Execute the shipped extraction scripts against framed school DOM fixtures.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '..');
function script(file, name) {
  const text = fs.readFileSync(path.join(root, file), 'utf8');
  const match = text.match(new RegExp(`const ${name} = r'''([\\s\\S]*?)''';`));
  assert.ok(match, name);
  return match[1];
}
const empty = {getElementById: () => null, querySelector: () => null};
const rows = [['節次','時間','星期二'], ['1','08:10~09:00','教師\n課程\nA101']];
const table = {innerText:'星期二', querySelectorAll: () => rows.map(r => ({querySelectorAll: () => r.map(innerText => ({innerText}))}))};
let clicks = 0;
const button = {dataset: {}, click: () => clicks++};
const scheduleDoc = {getElementById: id => id === 'table2' ? table : null, querySelector: () => button};
const inaccessible = {};
Object.defineProperty(inaccessible, 'document', {get() {throw new Error('cross origin');}});
const window = {document:empty, frames:[inaccessible, {document:scheduleDoc, frames:[]}]};
const schedule = script('lib/features/schedule/schedule_screen.dart','scheduleExtractScript');
// Catch invalid composition when an extraction expression is embedded in a user script.
new vm.Script(`(() => { const result = ${schedule}; return result; })()`);
assert.deepEqual(JSON.parse(vm.runInNewContext(schedule,{window,document:empty})),rows);
assert.deepEqual(JSON.parse(vm.runInNewContext(schedule,{window:{document:scheduleDoc,frames:[]},document:scheduleDoc})),rows);
assert.equal(vm.runInNewContext(schedule,{window:{document:empty,frames:[]},document:empty}),null);
require('./check_schedule_lifecycle');
const gradDoc = {
  getElementById: id => id === 'div_B' ? {innerText:'10 20 30 40'} : {innerText:'學程'},
  querySelector: () => ({closest: () => ({querySelector: () => ({innerText:'通過'})})}),
  querySelectorAll: () => [{cells:[{innerText:'畢業最低學分數'},{innerText:'128'},{innerText:'90'}]}],
};
const graduation = script('lib/features/graduation/graduation_screen.dart','graduationExtractScript');
new vm.Script(`(() => { const result = ${graduation}; return result; })()`);
const data = JSON.parse(vm.runInNewContext(graduation,{window:{document:empty,frames:[{document:gradDoc,frames:[]}]}}));
assert.deepEqual(data.diverseHours,['10','20','30','40']);
assert.equal(data.englishAbility,'通過');
assert.deepEqual(data.creditRequired,['128','90']);
assert.equal(vm.runInNewContext(graduation,{window:{document:empty,frames:[]}}),null);
assert.deepEqual(JSON.parse(vm.runInNewContext(graduation,{window:{document:gradDoc,frames:[]}})),data);
console.log('PASS: framed schedule/graduation extraction, inaccessible frames, delayed query readiness and single click');
