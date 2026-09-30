import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/features/events/event_actions.dart';

String node(String script) {
  final result = Process.runSync('node', ['-e', script]);
  expect(result.exitCode, 0, reason: result.stderr.toString());
  return '${result.stdout}';
}

void main() {
  test('scripts reply before pressing, so navigation cannot lose it', () {
    for (final script in [eventRegisterScript, eventCancelScript]) {
      node('''
const assert=require('node:assert/strict');
let clicked=0;const later=[];
global.setTimeout=(f)=>later.push(f);
const button={value:${jsonEncode(script == eventRegisterScript ? '我要報名' : '取消報名')},disabled:false,click:()=>clicked++};
const form={method:'post',querySelector:()=>({value:'t'}),querySelectorAll:()=>[button]};
global.document={forms:[form]};
assert.equal(eval(${jsonEncode(script)}),'submitted');
assert.equal(clicked,0);
later.forEach(f=>f());
assert.equal(clicked,1);
''');
    }
  });

  test('missing button is reported only when nothing matches', () {
    node('''
const assert=require('node:assert/strict');
const form={method:'post',querySelector:()=>({value:'t'}),querySelectorAll:()=>[{value:'返回',click(){throw 1}}]};
global.document={forms:[form]};
assert.equal(eval(${jsonEncode(eventRegisterScript)}),'missing');
''');
  });

  test('my registrations lookup matches the event link or exact title', () {
    node('''
const assert=require('node:assert/strict');
function page(hrefs,titles){return {
  querySelector:s=>s==='.container.body-content'?{}:null,
  querySelectorAll:s=>s==='a[href]'?hrefs.map(h=>({getAttribute:()=>h})):titles.map(t=>({textContent:t})),
};}
global.document=page(['/MvcTeam/Act/RegData/1234'],[]);
assert.equal(eval(${jsonEncode(eventListedScript('1234', '工作坊'))}),true);
global.document=page(['/MvcTeam/Act/RegData/12345'],['另一個活動']);
assert.equal(eval(${jsonEncode(eventListedScript('1234', '工作坊'))}),false);
global.document=page([],[' 工作坊 ']);
assert.equal(eval(${jsonEncode(eventListedScript('', '工作坊'))}),true);
''');
  });
}
