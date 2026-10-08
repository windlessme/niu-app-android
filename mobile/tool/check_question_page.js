// Runs the shipped question reader (moodleQuestionInstall) against the iOS
// repo's offline fixtures, so a script synced from iOS is checked the same way.
//
//   NODE_PATH=<folder with jsdom>/node_modules \
//     node tool/check_question_page.js <iOS repo>/scripts/check-moodle-question-page.py
//
// Needs jsdom (not a project dependency), so tool/verify.sh does not run it.
const fs = require('node:fs');
const path = require('node:path');
const { JSDOM, VirtualConsole } = require('jsdom');

const dart = fs.readFileSync(path.join(__dirname, '../lib/features/moodle/moodle_questions.dart'), 'utf8');
const install = dart.match(/const moodleQuestionInstall = r'''\n([\s\S]*?)\n''';/)[1];

// Cases are Swift tuples: ("name", #"""html"""#, #"""checks"""#).
const source = fs.readFileSync(process.argv[2], 'utf8');
const block = source.slice(source.indexOf('let cases'), source.indexOf('    ]\n\n    override init()'));
const cases = block.split(/\n {8}\("/).slice(1).map(part => {
  const name = part.slice(0, part.indexOf('"'));
  const raws = [...part.matchAll(/#"""\n([\s\S]*?)\n\s*"""#/g)].map(m => m[1]);
  // One case builds its page in Swift: a reading too long for a native summary.
  const html = raws.length === 2 ? raws[0] :
    "<main id='region-main'><p>" + '長篇題目'.repeat(5000) + "</p><button onclick='window.submits=1'>作答</button></main>";
  return { name, html, checks: raws[raws.length - 1] };
});

(async () => {
  let failed = 0, previous = '';
  for (const [index, c] of cases.entries()) {
    const url = 'https://euni.niu.edu.tw/mod/' + (c.name.startsWith('review ') ? 'quiz/review.php?attempt=10'
      : index === 0 ? 'quiz/view.php?id=100' : 'irs/view.php?id=100');
    const dom = new JSDOM("<meta charset='utf-8'>" + c.html,
      { url, runScripts: 'dangerously', pretendToBeVisual: true, virtualConsole: new VirtualConsole() });
    const w = dom.window;
    // jsdom has no layout: a box exists unless an ancestor is display:none.
    w.Element.prototype.getClientRects = function () {
      for (let e = this; e; e = e.parentElement) if (w.getComputedStyle(e).display === 'none') return [];
      return [{}];
    };
    w.Element.prototype.scrollIntoView = function () {};
    try {
      w.eval(install);
      const revision = JSON.parse(w.eval('JSON.stringify(window.__niuQuestionsV1.snapshot())')).revision;
      if (revision === previous) throw Error('reopening must create a new document identity');
      previous = revision;
      // As on iOS, stage and perform resolve promises.
      const body = c.checks.replace(/bridge\.(perform|stage)\(/g, 'await bridge.$1(').replace(/await await /g, 'await ');
      await new w.Function('return (async () => { const bridge = window.__niuQuestionsV1;' +
        'function require(v, m) { if (!v) throw Error(m); }' + body + '})()')();
      console.log('PASS: ' + c.name);
    } catch (e) {
      failed++;
      console.log('FAIL: ' + c.name + ': ' + (e && e.message));
    }
    w.close();
  }
  console.log(`${cases.length - failed}/${cases.length} fixtures passed`);
  process.exit(failed || !cases.length ? 1 : 0);
})();
