import 'dart:convert';

/// Every operation checks the original top document and the exact school form.
/// No cookies, viewstate, identity fields or authentication URLs cross the bridge.
String leaveApplicationScript(
  String run,
  String operation, [
  Map<String, dynamic> args = const {},
]) =>
    '''
(() => {
 const run=${jsonEncode(run)}, op=${jsonEncode(operation)}, args=${jsonEncode(args)};
 $leaveApplicationRuntime
})()
''';

const leaveApplicationRuntime = r'''
 const allowed=d=>{try{const u=new URL(d.location.href);return u.origin==='https://acade.niu.edu.tw';}catch(_){return false;}};
 if(!allowed(document))return JSON.stringify({error:'校務頁面尚未就緒'});
 const root=window;
 const previous=root.__niuPersonalLeave;
 if(previous && previous.run!==run)return JSON.stringify({error:'校務頁面已變更，請重新開啟申請'});
 const state=previous||(root.__niuPersonalLeave={run,sequence:0});
 const docs=[];
 function collect(w){try{if(allowed(w.document))docs.push(w.document);for(let i=0;i<w.frames.length;i++)collect(w.frames[i]);}catch(_){}}
 collect(root);
 const path=d=>new URL(d.location.href).pathname;
 if(docs.some(d=>/\/(?:TimeOutPage|logout|default)\.aspx$/i.test(path(d))))return JSON.stringify({error:'校務登入已過期，請重新登入後重新開啟申請'});
 // An existing form opens in viewFrame; match it by file name as iOS does.
 const find=p=>docs.find(d=>path(d)===p)||docs.find(d=>path(d).toLowerCase().endsWith(p.slice(p.lastIndexOf('/')).toLowerCase()));
 const main=find('/NIU/Application/SEC/SEC20/SEC2010_01.aspx');
 const notice=find('/NIU/Application/SEC/SEC20/SEC2010_02.aspx');
 const picker=find('/NIU/Application/SEC/SEC20/SEC2010_03.aspx');
 const clean=s=>String(s||'').replace(/\s+/g,' ').trim();
 const value=(d,id)=>d.getElementById(id)?.value||'';
 const text=(d,id)=>clean(d.getElementById(id)?.textContent);
 const pending=d=>d.readyState!=='complete'||!!d.defaultView.Sys?.WebForms?.PageRequestManager?.getInstance()?.get_isInAsyncPostBack();
 const error=message=>JSON.stringify({error:message});
 // A new application has no form number; modify (MOD) and supplement (DETAIL)
 // work only on the one form they were opened for, in that mode.
 const formNo=args.formNo||'', mode=String(args.mode||'').toUpperCase();
 const formMode=d=>value(d,'Mode').toUpperCase();
 const ours=d=>formNo?value(d,'M_FORM_NO')===formNo&&formMode(d)===mode:!value(d,'M_FORM_NO');
 function track(d){
   if(!d.__niuLeaveRevision){
     d.__niuLeaveRevision={id:Math.random().toString(36).slice(2),count:0};
     const manager=d.defaultView.Sys?.WebForms?.PageRequestManager?.getInstance();
     if(manager)manager.add_endRequest(()=>d.__niuLeaveRevision.count++);
   }
   return d.__niuLeaveRevision.id+':'+d.__niuLeaveRevision.count;
 }
 function revision(d){return track(d);}
 function newReceipt(d){state.receipt={id:String(++state.sequence),revision:revision(d)};return state.receipt;}
 function uploadDoc(){return docs.find(d=>path(d)==='/NIU/utility/UploadFile_HasUseId.aspx');}
 // The school grid shows [delete, 預覽 link, 說明]; the file's label is 說明.
 function uploadNames(upload){
   const tables=Array.from(upload.querySelectorAll('table')).filter(t=>t.id==='UploadGrid');
   const grid=tables[tables.length-1];if(!grid)return [];
   return Array.from(grid.rows).filter(r=>!r.querySelector('th')&&r.cells.length>=3)
     .map(r=>clean(r.cells[r.cells.length-1].innerText)||clean(r.querySelector('a')?.textContent)).filter(Boolean);
 }
 function snapshot(){
   if(notice&&!pending(notice))return {revision:revision(notice),notice:notice.body.innerText.trim()};
   if(!main||pending(main))return null;
   if(!ours(main))return null; // Never edit any other application.
   const student=text(main,'M_STNO').toLowerCase();
   if(!student||student!==args.owner?.toLowerCase())return {error:'校方表單身分無法確認'};
   const type=main.getElementById('M_HOLIDAY_CODE'), reason=main.getElementById('M_APP_ORIGIN');
   if(!type||!reason||!main.getElementById('SEND_BTN1'))return {error:'校方表單格式已變更'};
   const label=Array.from(main.querySelectorAll('[ml]')).find(e=>clean(e.textContent)==='本次請假日期與節次明細');
   const table=label?.closest('tr')?.querySelector('table')||Array.from(main.querySelectorAll('table')).find(t=>t.rows[0]?.textContent.includes('請假節次'));
   const periods=table?Array.from(table.rows).slice(1).filter(r=>r.cells.length>1&&!/查無|無資料/.test(r.textContent)).map(r=>Array.from(r.cells,c=>clean(c.innerText))):[];
   const periodHeaders=table?.rows[0]?Array.from(table.rows[0].cells,c=>clean(c.innerText)):[];
   const countLabel=Array.from(main.querySelectorAll('[ml]')).find(e=>clean(e.textContent)==='本次請假總節數');
   const total=clean(countLabel?.closest('td')?.nextElementSibling?.innerText)||null;
   const upload=uploadDoc();
   const attachments=upload?uploadNames(upload):[];
   const extensions=(upload?value(upload,'filter'):'').split(',').map(s=>s.trim().toLowerCase()).filter(s=>/^[a-z0-9]+$/.test(s));
   const later=main.getElementById('CheckBox1');
   return {revision:revision(main),choices:Array.from(type.options).filter(o=>!o.disabled).map(o=>({value:o.value,label:o.text})),type:type.value,
     start:value(main,'M_HOLIDAY_DATE_S'),end:value(main,'M_HOLIDAY_DATE_E'),reason:reason.value,reasonLimit:reason.maxLength,
     later:!!later?.checked,canDeferAttachment:!!later&&!later.disabled,periods,periodHeaders,total,attachments,extensions,
     formNo:value(main,'M_FORM_NO'),mode:formMode(main),submitLabel:value(main,'SEND_BTN1'),editable:!type.disabled};
 }
 if(op==='read')return JSON.stringify(snapshot());
 if(op==='settled'){
   if(!state.receipt||state.receipt.id!==args.receipt)return null;
   const d=args.kind==='agree'?main:main;
   if(!d||pending(d)||revision(d)===state.receipt.revision)return null;
   return JSON.stringify(snapshot());
 }
 if(op==='periods'){
   if(!picker||pending(picker))return null;
   const table=picker.getElementById('table2');if(!table)return error('無法讀取可選節次');
   const dates=Array.from(table.rows[0]?.cells||[],c=>clean(c.innerText));
   const periods=[];
   for(const row of Array.from(table.rows).slice(1)){
     for(let i=1;i<row.cells.length;i++)for(const input of row.cells[i].querySelectorAll('input[type="checkbox"][name="chkBox"]')){
       // The cell lists teacher, course and room on separate lines, as iOS reads it.
       const lines=String(row.cells[i].innerText||'').split('\n').map(clean).filter(Boolean);
       if(!input.disabled)periods.push({value:input.value,date:dates[i]||'',period:clean(row.cells[0].innerText),course:lines.length>1?lines[1]:clean(row.cells[i].innerText),teacher:lines.length>1?lines[0]:'',room:lines[2]||'',selected:input.checked});
     }
   }
   return JSON.stringify({periods,revision:revision(picker)});
 }
 if(op==='submissionResult'){
   if(!state.submitted)return null;
   if(formNo){
     // An existing form keeps its number: the school having handled the
     // click (a postback or a new page) is all that can be observed here.
     if(main&&(pending(main)||revision(main)===state.submitRevision))return null;
     return JSON.stringify({sent:true});
   }
   if(!main||pending(main))return null;
   const id=value(main,'M_FORM_NO');
   const owner=text(main,'M_STNO').toLowerCase();
   // Only a new server-rendered number on the same student's form is evidence.
   const flow=main.getElementById('FLOW_BTN');
   if(id && owner===args.owner?.toLowerCase() && revision(main)!==state.submitRevision && flow && !flow.disabled){
     return JSON.stringify({applicationId:id,message:'學校已建立假單，請至請假紀錄確認審核狀態。'});
   }
   return null;
 }
 if(op==='agree'){
   if(!notice||pending(notice)||revision(notice)!==args.revision)return error('請假注意事項已更新');
   const button=notice.getElementById('SAVE_BTN2');
   if(!button||button.value!=='同意'||button.disabled)return error('無法確認注意事項');
   const receipt=newReceipt(notice);notice.defaultView.setTimeout(()=>button.click(),0);
   return JSON.stringify(receipt);
 }
 if(!main||pending(main)||!ours(main))return error('校方申請表單無法編輯');
 if(text(main,'M_STNO').toLowerCase()!==args.owner?.toLowerCase())return error('校方表單身分無法確認');
 if(state.submitted)return error('已嘗試送出，請先查詢紀錄，勿重複送出');
 // 補檔: every field is locked; only attachments change, then「送出」.
 if(mode==='DETAIL'&&!['uploadStart','uploadChunk','uploadSend','uploadResult','submit'].includes(op))return error('補交證明文件只能附加檔案');
 if(op==='cancelPeriods'){
   if(picker)picker.defaultView.parent.jQuery.fancybox.close();return JSON.stringify({ok:true});
 }
 if(op==='uploadChunk'){
   if(!state.upload||state.upload.id!==args.id)return error('附件準備已失效');
   if(state.upload.size+args.chunk.length>14*1024*1024)return error('附件超過 App 處理上限');
   state.upload.parts.push(args.chunk);state.upload.size+=args.chunk.length;return JSON.stringify({ok:true});
 }
 if(revision(main)!==args.revision)return error('表單已變更，請重新確認內容');
 if(op==='type'||op==='date'){
   const id=op==='type'?'M_HOLIDAY_CODE':args.field;
   if(!['M_HOLIDAY_CODE','M_HOLIDAY_DATE_S','M_HOLIDAY_DATE_E'].includes(id))return error('不允許的欄位');
   const input=main.getElementById(id);if(!input||input.disabled)return error('欄位不可編輯');
   if(op==='type' && !Array.from(input.options).some(o=>o.value===args.value&&o.value!=='003'&&!o.text.includes('公假')&&!o.disabled))return error('不支援此假別');
   if(op==='date'&&!/^\d{3}\/\d{2}\/\d{2}$/.test(args.value))return error('日期格式不符');
   const receipt=newReceipt(main);input.value=args.value;
   // ASP.NET's legacy caller inspection requires its own non-strict timer stack.
   main.defaultView.setTimeout('__doPostBack('+JSON.stringify(id)+', "")',0);
   return JSON.stringify(receipt);
 }
 if(op==='openPeriods'){
   if(!value(main,'M_HOLIDAY_DATE_S')||!value(main,'M_HOLIDAY_DATE_E'))return error('請先選擇日期');
   const button=main.getElementById('OPENCLASS');if(!button||button.disabled)return error('無法開啟節次');
   main.defaultView.setTimeout(()=>button.click(),0);return JSON.stringify({ok:true});
 }
 if(op==='applyPeriods'){
   if(!picker||pending(picker)||revision(picker)!==args.pickerRevision)return error('節次頁面已變更');
   const inputs=Array.from(picker.querySelectorAll('input[type="checkbox"][name="chkBox"]'));
   if(!args.values.length||!args.values.every(v=>inputs.some(e=>e.value===v&&!e.disabled)))return error('包含不可選的節次');
   for(const input of inputs)if(!input.disabled)input.checked=args.values.includes(input.value);
   const button=picker.getElementById('BACK_BTN1');if(!button||button.value!=='帶回'||button.disabled)return error('無法帶回節次');
   const receipt=newReceipt(main);picker.defaultView.setTimeout(()=>button.click(),0);return JSON.stringify(receipt);
 }
 if(op==='draft'){
   const reason=main.getElementById('M_APP_ORIGIN');
   if(!reason||args.reason.length>reason.maxLength)return error('事由超過字數限制');
   reason.value=args.reason;
   const later=main.getElementById('CheckBox1');
   if(args.later&&(!later||later.disabled))return error('校方未開放事後補檔');
   if(later&&!later.disabled)later.checked=args.later;
   return JSON.stringify(snapshot());
 }
 if(op==='uploadStart'){
   const upload=uploadDoc();if(!upload||pending(upload))return error('附件頁面尚未就緒');
   const extension=args.name.split('.').pop().toLowerCase();
   const permitted=value(upload,'filter').split(',').map(s=>s.trim().toLowerCase());
   if(!permitted.includes(extension))return error('校方不支援此附件格式');
   state.upload={id:String(++state.sequence),parts:[],size:0,name:args.name,revision:revision(upload)};
   return JSON.stringify({id:state.upload.id});
 }
 if(op==='uploadSend'){
   const upload=uploadDoc(), file=state.upload;
   if(!upload||pending(upload)||!file||file.id!==args.id||revision(upload)!==file.revision)return error('附件頁面已變更');
   const input=upload.getElementById('tmpfile'), button=upload.getElementById('attach');
   const form=input?.form;
   const action=form?new URL(form.action,upload.location.href):null;
   if(!input||input.type!=='file'||!button||button.disabled||!form||form.method.toLowerCase()!=='post'||form.enctype!=='multipart/form-data'||action.origin!=='https://acade.niu.edu.tw'||action.pathname!=='/NIU/utility/UploadFile_HasUseId.aspx')return error('附件表單格式已變更');
   const w=upload.defaultView;
   const bytes=Uint8Array.from(atob(file.parts.join('')),c=>c.charCodeAt(0));
   const transfer=new w.DataTransfer();transfer.items.add(new w.File([bytes],file.name));input.files=transfer.files;
   // The school page fills 說明 from the file name on blur; do the same.
   const remark=upload.getElementById('remark');
   const label=file.name.replace(/\.[^.]*$/,'').slice(0,200);
   if(remark&&!remark.value)remark.value=label;
   file.parts=[];state.uploadAttempt={name:file.name,label:remark?remark.value:label,before:uploadNames(upload).length,revision:file.revision};state.upload=null;
   w.setTimeout(()=>button.click(),0);return JSON.stringify({ok:true});
 }
 if(op==='uploadResult'){
   const upload=uploadDoc(), attempt=state.uploadAttempt;
   if(!upload||pending(upload)||!attempt||revision(upload)===attempt.revision)return null;
   // The frame reloaded after 附加: a new row (or our label) means it was kept.
   const names=uploadNames(upload);
   if(names.length>attempt.before||names.includes(attempt.label))return JSON.stringify(snapshot());
   return error('學校沒有收到附件，請到學校網頁確認');
 }
 if(op==='submit'){
   const type=main.getElementById('M_HOLIDAY_CODE');
   if(mode!=='DETAIL'&&(!type?.value||type.value==='003'||type.selectedOptions[0]?.text.includes('公假')))return error('請選擇一般請假假別');
   const button=main.getElementById('SEND_BTN1');
   if(!button||button.value!==(mode==='MOD'?'修改':'送出')||button.disabled)return error('校方未開放送出');
   const form=button.form, action=form?new URL(form.action,main.location.href):null;
   if(!form||form.method.toLowerCase()!=='post'||action.origin!=='https://acade.niu.edu.tw'||action.pathname!==path(main))return error('校方送出表單已變更');
   const checked=snapshot();
   if(!checked || ['type','start','end','reason','later'].some(k=>checked[k]!==args.expected?.[k]) || JSON.stringify(checked.periods)!==JSON.stringify(args.expected?.periods))return error('申請內容已變更，請重新確認');
   state.submitted=true;state.submitRevision=revision(main);
   main.defaultView.setTimeout(()=>button.click(),0);return JSON.stringify({ok:true});
 }
 return error('不支援的請假操作');
''';
