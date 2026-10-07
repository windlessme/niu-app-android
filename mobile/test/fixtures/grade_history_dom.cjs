// Runs the shipped 歷年成績 extract script against a hand-built copy of the
// page: the summary and every course table sit in div.row, and course rows
// start with the same 學年期 value as summary rows.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const s = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));

const cell = text => ({textContent: text});
const row = (texts, head) => ({querySelectorAll: sel =>
  sel === 'th,td' || sel === (head ? 'th' : 'td') ? texts.map(cell) : []});
const table = (rows, inAccordion) => ({
  closest: sel => sel === '#accordion修課紀錄' && inAccordion ? {} : null,
  querySelectorAll: sel => sel === 'tr' ? rows : []});
const summary = table([
  row(['學年期', '系排名(名次/人數)', '班排名(名次/人數)', '學業平均成績'], true),
  row(['1141', '12 / 90', '46 / 55', '70.36']),
  row(['1142', '第 名', '第 名', '']),
], false);
const courses = ['1141', '1142'].map(sem => table([
  row(['學年期', '選別', '學分數', '課程名稱', '修課成績'], true),
  row([sem, '必修', '3', '微積分', '80']),
], true));
const striped = courses.flatMap(t => t.querySelectorAll('tr'));
const doc = {querySelector: sel => sel === '#accordion修課紀錄' ? {} : null,
  querySelectorAll: sel => sel === 'table.table' ? [summary, ...courses]
    : sel === '#accordion修課紀錄 table.table.table-striped tr' ? striped : []};
const context = vm.createContext({window: {document: doc, frames: {length: 0}}, JSON, Array, String});
const value = JSON.parse(vm.runInContext(s.history, context));
assert.equal(value.rows.length, 2);
// Credits (3) and course names must never be read as rank or average.
assert.deepEqual(value.ranks, [
  {sem: '1141', classRank: '46 / 55', departmentRank: '12 / 90', average: '70.36'},
  {sem: '1142', classRank: '第 名', departmentRank: '第 名', average: ''},
]);
