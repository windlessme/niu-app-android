import 'dart:convert';
import '../../core/session/campus_session.dart';

/// Private snapshots, scoped to the current account and drained during logout.
class LeaveRepository {
  LeaveRepository(this.session) {
    session.registerCleanup(clear);
  }
  final CampusSession session;
  Future<void>? _write;
  void guard(int epoch, String owner) {
    session.coordinator.requireCurrent(epoch);
    if (!session.hasLocalAccount || session.account != owner) {
      throw StateError('Session changed');
    }
  }

  Future<Map<String, dynamic>> restore() async {
    final owner = session.account;
    if (owner == null) return {};
    final epoch = session.coordinator.epoch;
    final raw = await session.vault.read('leaveCache');
    guard(epoch, owner);
    try {
      final data = jsonDecode(raw ?? '') as Map<String, dynamic>;
      if (data['version'] != 1 ||
          data['account'] != owner ||
          data['snapshots'] is! Map) {
        return {};
      }
      final snapshots = Map<String, dynamic>.from(data['snapshots'] as Map);
      validate(snapshots);
      return snapshots;
    } catch (_) {
      return {};
    }
  }

  Future<void> save(
    Map<String, dynamic> snapshots,
    int epoch,
    String owner,
  ) async {
    guard(epoch, owner);
    validate(snapshots);
    final raw = jsonEncode({
      'version': 1,
      'account': owner,
      'snapshots': snapshots,
    });
    final previous = _write;
    final task = () async {
      try {
        await previous;
      } catch (_) {}
      guard(epoch, owner);
      await session.vault.write('leaveCache', raw);
      guard(epoch, owner);
    }();
    _write = task;
    await task;
  }

  Future<void> clear() async {
    try {
      await _write;
    } catch (_) {}
  }

  static void validate(Map<String, dynamic> snapshots) {
    for (final entry in snapshots.entries) {
      final envelope = entry.value;
      if (envelope is! Map ||
          DateTime.tryParse('${envelope['updatedAt']}') == null ||
          envelope['data'] is! Map) {
        throw const FormatException('Invalid leave cache');
      }
      final data = envelope['data'] as Map;
      if (entry.key == 'statistics') {
        if (data['periods'] is! Map ||
            (data['periods'] as Map).values.any((v) => v is! String)) {
          throw const FormatException('Invalid statistics');
        }
      } else if (entry.key == 'list') {
        if (data['records'] is! List ||
            (data['records'] as List).any(
              (v) => v is! Map || v['假單序號'] is! String,
            )) {
          throw const FormatException('Invalid records');
        }
      } else if (entry.key.startsWith('detail:')) {
        if (data['fields'] is! Map ||
            data['periods'] is! List ||
            (data['periods'] as List).any(
              (t) => t is! List || t.any((r) => r is! List),
            )) {
          throw const FormatException('Invalid detail');
        }
        if (data.containsKey('workflow') &&
            (data['workflow'] is! List ||
                (data['workflow'] as List).any(
                  (step) =>
                      step is! Map ||
                      [
                        '簽核狀況',
                        '簽核日期',
                        '關卡說明',
                        '簽核單位',
                      ].any((key) => step[key] is! String),
                ))) {
          throw const FormatException('Invalid workflow');
        }
      } else {
        throw const FormatException('Unknown snapshot');
      }
    }
  }

  Future<void> dispose() async {
    await clear();
    session.unregisterCleanup(clear);
  }
}

final leaveApplication = Uri.parse(
  'https://acade.niu.edu.tw/NIU/Application/SEC/SEC20/SEC2010_.aspx?progcd=SEC2010',
);
final leaveQuery = Uri.parse(
  'https://acade.niu.edu.tw/NIU/Application/SEC/SEC40/SEC4030_01.aspx',
);

String leaveMenuNavigation(
  bool application, {
  bool agreeForStatistics = false,
}) =>
    '''
(() => {
 const docs=[];function collect(w){try{docs.push(w.document);for(let i=0;i<w.frames.length;i++)collect(w.frames[i]);}catch(_){}}collect(window);
 for(const d of docs){if(new URL(d.location.href).pathname.toLowerCase().endsWith('/timeoutpage.aspx'))return 'session-expired';}
 if(window.__niuLeaveWorkflowDetail)return 'ready';
 for(const d of docs){
  const path=new URL(d.location.href).pathname;
  if(path.includes('/SEC/')) {
   if(path.endsWith('/SEC2010_02.aspx')) {
     if(${agreeForStatistics ? 'true' : 'false'}) {
       const button=d.getElementById('SAVE_BTN2');
       if(button && button.value==='同意' && !button.disabled && !d.__niuLeaveAgreed) {
         d.__niuLeaveAgreed=true;button.click();
       }
       return null;
     }
     return 'interaction-required';
   }
   if(!${application ? 'true' : 'false'} && path.endsWith('/SEC4030_01.aspx'))return 'ready';
   return 'ready';
  }
 }
 for(const label of ${jsonEncode(application ? ['學務系統', '學生請假', '學生請假作業', '學生請假申請'] : ['學務系統', '學生請假', '查詢作業', '請假紀錄'])}){
  for(const d of docs){const a=Array.from(d.querySelectorAll('a')).find(e=>e.textContent.trim()===label);
   if(a && !a.dataset.niuLeaveOpened){a.dataset.niuLeaveOpened='true';a.click();return null;}}
 }
 return null;
})()
''';

/// A read-only query postback. Its settled table, not a navigation event, is the result.
const leaveQueryPrepare = r'''
(() => {
 const d = document;
 if (!location.pathname.endsWith('/SEC4030_01.aspx')) return false;
 if (!d.__niuLeaveQueried) {
   const button=d.getElementById('QUERY_BTN1');
   if (!button || button.disabled) return false;
   d.__niuLeaveQueried=true;
   button.click(); return false;
 }
 const manager=window.Sys?.WebForms?.PageRequestManager?.getInstance();
 if (manager?.get_isInAsyncPostBack()) return false;
 return !!d.getElementById('DataGrid');
})()
''';

String leavePagePrepare(int page) =>
    '''
(() => {
 const ready=(0,eval)(${jsonEncode(leaveQueryPrepare)});if(!ready)return false;
 const input=document.getElementById('PC_PageNo');
 if(!input || $page===1)return true;
 if(!document.__niuLeavePage){document.__niuLeavePage=true;input.value='$page';document.getElementById('PC_ToGo')?.click();return false;}
 const manager=window.Sys?.WebForms?.PageRequestManager?.getInstance();
 return !manager?.get_isInAsyncPostBack() && input.value==='$page';
})()
''';

const leaveListExtract = r'''
(() => {
 const table=document.getElementById('DataGrid');
 if (!location.pathname.endsWith('/SEC4030_01.aspx') || !table) return null;
 const clean=v=>String(v||'').replace(/\s+/g,' ').trim();
 const headers=Array.from(table.rows[0]?.cells||[],c=>clean(c.textContent));
 if (!headers.includes('假單序號') || !headers.includes('審核結果')) return null;
 const records=Array.from(table.rows).slice(1).filter(r=>r.cells.length===headers.length).map(r=>Object.fromEntries(headers.map((h,i)=>[h,clean(r.cells[i].textContent)])));
 return JSON.stringify({records,page:clean(document.getElementById('PC_PageNo')?.value),pages:clean(document.getElementById('PC_TotalPage')?.textContent),total:clean(document.getElementById('PC_TotalRow')?.textContent)});
})()
''';

const leaveStatisticsExtract = r'''
(() => {
 const docs=[];function collect(w){try{docs.push(w.document);for(let i=0;i<w.frames.length;i++)collect(w.frames[i]);}catch(_){}}collect(window);
 for(const d of docs){
  const label=d.querySelector('[ml="PL_本學期請假節數統計"]');
  const table=label?.closest('tr')?.querySelector('table');
  if(!table || table.rows.length!==2)continue;
  const labels=Array.from(table.rows[0].cells,c=>c.textContent.trim());
  const values=Array.from(table.rows[1].cells,c=>c.textContent.trim());
  if(labels.length!==values.length)continue;
  return JSON.stringify({periods:Object.fromEntries(labels.map((l,i)=>[l,values[i]])),scope:'本學期'});
 }
 return null;
})()
''';

/// Opens one record's detail from the query list, then the school's own
/// workflow modal. The record may have moved since the list was cached, so
/// every result page is searched, starting with the page it was seen on.
String leaveDetailPrepare(String id, int page) =>
    '''
(() => {
 const docs=[];function collect(w){try{docs.push(w.document);for(let i=0;i<w.frames.length;i++)collect(w.frames[i]);}catch(_){}}collect(window);
 if(window.__niuLeaveWorkflowDetail)return true;
 for(const d of docs){
  if(!d.location.pathname.endsWith('/SEC2010_04.aspx') || d.readyState!=='complete')continue;
  const raw=(0,eval)(${jsonEncode(leaveDetailExtract)});
  if(!raw)return false;
  const button=d.getElementById('FLOW_BTN');
  window.__niuLeaveWorkflowDetail=JSON.parse(raw);
  if(!button || button.disabled){window.__niuLeaveWorkflowUnavailable=true;return true;}
  // Use the school's own modal and parameters in the original frame/session.
  button.click();return false;
 }
 const list=docs.find(d=>d.location.pathname.endsWith('/SEC4030_01.aspx'));
 if(!list)return false;
 if(!list.defaultView.eval(${jsonEncode(leaveQueryPrepare)}))return false;
 const manager=list.defaultView.Sys?.WebForms?.PageRequestManager?.getInstance();
 if(manager?.get_isInAsyncPostBack())return false;
 const table=list.getElementById('DataGrid');if(!table||!table.rows.length)return false;
 const clean=v=>String(v||'').replace(/\\s+/g,' ').trim();
 const now=Date.now();
 // Session storage survives full-page postbacks while paging.
 const key='niu.leave.find.'+${jsonEncode(id)};
 const store=list.defaultView.sessionStorage;
 let state=window.__niuLeaveFind;
 if(!state){try{state=JSON.parse(store.getItem(key));}catch(_){}}
 const run=list.defaultView.__niuAcademicRun||window.__niuAcademicRun||'';
 if(!state||state.run!==run||now-state.started>90000)state={run,started:now,visited:[],target:null,at:0,clicked:0};
 window.__niuLeaveFind=state;
 const save=()=>{try{store.setItem(key,JSON.stringify(state));}catch(_){}};
 const input=list.getElementById('PC_PageNo');
 const current=parseInt(input?.value,10)||1;
 if(state.target!==null && state.target!==current && now-state.at<8000)return false;
 state.target=null;
 if(!state.visited.includes(current))state.visited.push(current);
 const headers=Array.from(table.rows[0].cells,c=>clean(c.textContent));
 const index=headers.indexOf('假單序號');
 const row=index<0?null:Array.from(table.rows).slice(1).find(r=>clean(r.cells[index]?.textContent)===${jsonEncode(id)});
 if(row){
  const link=row.querySelector('a[href*="doNewEdit"]')||row.querySelector('a[href^="javascript" i],a[onclick],a[href]')||row.querySelector('input[type="button"],input[type="submit"],input[type="image"],button,[onclick]');
  // Retry if the school page ignored a click; the detail page replaces this list.
  if(link && now-state.clicked>4000){state.clicked=now;save();link.click();}
  return false;
 }
 const total=parseInt(clean(list.getElementById('PC_TotalPage')?.textContent),10)||1;
 const order=[$page];for(let p=1;p<=total;p++)order.push(p);
 const next=order.find(p=>p>=1&&p<=total&&!state.visited.includes(p));
 const go=list.getElementById('PC_ToGo');
 if(next===undefined||!input||!go)return false;
 state.target=next;state.at=now;save();input.value=String(next);go.click();
 return false;
})()
''';

String leaveInFrames(String script) =>
    '''
(() => {
 function run(w){try {const value=w.eval(${jsonEncode(script)});if(value)return value;for(let i=0;i<w.frames.length;i++){const result=run(w.frames[i]);if(result)return result;}}catch(_){}return null;}
 return run(window);
})()
''';

String leaveDetailWithWorkflowExtract() =>
    '''
(() => {
 const detail=window.__niuLeaveWorkflowDetail;
 if(!detail)return null;
 if(window.__niuLeaveWorkflowUnavailable)return JSON.stringify(detail);
 const result=(0,eval)(${jsonEncode(leaveInFrames(leaveWorkflowExtract))});
 if(!result)return null;
 return JSON.stringify({...detail,...JSON.parse(result)});
})()
''';

const leaveDetailExtract = r'''
(() => {
 const docs=[];function collect(w){try{docs.push(w.document);for(let i=0;i<w.frames.length;i++)collect(w.frames[i]);}catch(_){}}collect(window);
 for(const d of docs){
  if(!d.location.pathname.endsWith('/SEC2010_04.aspx'))continue;
  const fields={};
  for(const label of d.querySelectorAll('span[ml^="PL_"]')){
   const name=label.textContent.trim();
   if(!['申請日期','請假類別','請假日期','本次請假總節數','請假事由','檢附證明文件'].includes(name))continue;
   const cell=label.closest('td')?.nextElementSibling;if(!cell)continue;
   const inputs=Array.from(cell.querySelectorAll('input:not([type="hidden"]):not([type="button"]),textarea,select'));
   fields[name]=(inputs.length?inputs.map(e=>e.tagName==='SELECT'?e.selectedOptions[0]?.text:e.value).join(' '):cell.innerText).trim();
  }
  const periods=Array.from(d.querySelectorAll('table')).filter(t=>t.rows[0]?.textContent.includes('請假節次')).map(t=>Array.from(t.rows,r=>Array.from(r.cells,c=>c.innerText.trim())));
  const code=d.getElementById('H_FORM_CODE')?.value;
  const flow=d.getElementById('H_APPROVE_FLOW_CODE')?.value;
  const group=d.getElementById('H_GROUP_APPLY_NO')?.value;
  let workflowUrl=null;
  if(code && flow && group){
    const url=new URL('/NIU/Application/FLO/FLO30/FLO3040_01.aspx',d.location.href);
    url.search=new URLSearchParams({FORM_CODE:code,APPROVE_FLOW_CODE:flow,GROUP_APPLY_NO:group,STAFF_ID:''}).toString();workflowUrl=url.href;
  }
  return JSON.stringify({fields,periods,workflowUrl});
 }return null;
})()
''';

bool isLeaveWorkflowUri(Uri uri) =>
    uri.scheme == 'https' &&
    uri.host == 'acade.niu.edu.tw' &&
    uri.port == 443 &&
    uri.userInfo.isEmpty &&
    uri.path == '/NIU/Application/FLO/FLO30/FLO3040_01.aspx';

const leaveWorkflowExtract = r'''
(() => {
 if(location.hostname!=='acade.niu.edu.tw' || location.pathname!=='/NIU/Application/FLO/FLO30/FLO3040_01.aspx')return null;
 const table=document.getElementById('DataGrid');if(!table)return null;
 const clean=v=>String(v||'').replace(/\s+/g,' ').trim();
 const headers=Array.from(table.rows[0]?.cells||[],c=>clean(c.textContent));
 const fields=['簽核狀況','簽核日期','關卡說明','簽核單位'];
 if(!fields.every(f=>headers.includes(f)))return null;
 const workflow=Array.from(table.rows).slice(1).filter(r=>r.cells.length===headers.length)
   .map(r=>Object.fromEntries(fields.map(f=>[f,clean(r.cells[headers.indexOf(f)].textContent)])));
 return JSON.stringify({workflow});
})()
''';
