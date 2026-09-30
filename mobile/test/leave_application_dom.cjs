const assert = require('node:assert/strict');
const vm = require('node:vm');
const runtime = process.argv[2];
const scripts = [];
let callbacks = [], pending = false;
const fields = {
  M_STNO: {textContent: 'B123'}, M_FORM_NO: {value: ''},
  M_HOLIDAY_CODE: {value: '023', options: [{value:'023',text:'事假'},{value:'003',text:'公假'}],selectedOptions:[{text:'事假'}]},
  M_HOLIDAY_DATE_S: {value:'115/10/01'},M_HOLIDAY_DATE_E:{value:'115/10/01'},
  M_APP_ORIGIN:{value:'fixture',maxLength:1000},CheckBox1:{checked:false},
  SEND_BTN1:{value:'送出',disabled:false,click:()=>scripts.push('SUBMIT')},
  FLOW_BTN:{disabled:true},OPENCLASS:{disabled:false,click:()=>scripts.push('PICKER')},
};
const manager={get_isInAsyncPostBack:()=>pending,add_endRequest:cb=>callbacks.push(cb)};
fields.SEND_BTN1.form={action:'https://acade.niu.edu.tw/NIU/Application/SEC/SEC20/SEC2010_01.aspx',method:'post'};
const doc={location:{href:'https://acade.niu.edu.tw/NIU/Application/SEC/SEC20/SEC2010_01.aspx'},readyState:'complete',
  getElementById:id=>fields[id],querySelectorAll:()=>[],body:{innerText:'form'}};
const w={document:doc,frames:[],Sys:{WebForms:{PageRequestManager:{getInstance:()=>manager}}},setTimeout:cb=>scripts.push(cb)};
doc.defaultView=w;
const context=vm.createContext({window:w,document:doc,URL,URLSearchParams,Uint8Array,JSON,Math,run:'fixture',op:'',args:{}});
const execute=(op,args={})=>{context.op=op;context.args={owner:'b123',...args};const r=vm.runInContext('(()=>{'+runtime+'})()',context);return r==null?null:JSON.parse(r);};
const first=execute('read');assert.equal(first.type,'023');assert.equal(first.total,null);
assert.equal(execute('type',{revision:first.revision,value:'003'}).error,'不支援此假別');
assert.equal(scripts.length,0);
const receipt=execute('date',{revision:first.revision,field:'M_HOLIDAY_DATE_S',value:'115/10/02'});
assert.ok(receipt.id);assert.equal(scripts.length,1);
assert.equal(execute('settled',{receipt:receipt.id}),null);
callbacks.forEach(cb=>cb());
const next=execute('settled',{receipt:receipt.id});assert.equal(next.start,'115/10/02');
assert.notEqual(next.revision,first.revision);
assert.ok(execute('type',{revision:first.revision,value:'023'}).error);
assert.ok(execute('draft',{revision:next.revision,owner:'other',reason:'reason',later:false}).error);
assert.ok(execute('submit',{revision:next.revision,expected:{...next,reason:'tampered'}}).error);
assert.ok(execute('submit',{revision:next.revision,expected:next}).ok);
assert.ok(execute('submit',{revision:next.revision}).error);
assert.equal(scripts.filter(s=>typeof s==='function').length,1);
assert.equal(execute('submissionResult'),null);
fields.M_FORM_NO.value='fixture-001';fields.FLOW_BTN.disabled=false;callbacks.forEach(cb=>cb());
assert.equal(execute('submissionResult').applicationId,'fixture-001');
doc.location.href='https://evil.test/NIU/Application/SEC/SEC20/SEC2010_01.aspx';
assert.ok(execute('read').error);
console.log('PASS: form origin, identity, revision, public leave, sequential postback and one-shot submit guards');
