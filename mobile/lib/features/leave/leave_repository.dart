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

String leaveMenuNavigation(bool application) =>
    '''
(() => {
 const docs=[];function collect(w){try{docs.push(w.document);for(let i=0;i<w.frames.length;i++)collect(w.frames[i]);}catch(_){}}collect(window);
 for(const d of docs){
  const path=new URL(d.location.href).pathname;
  if(path.includes('/SEC/')) {
   if(path.endsWith('/SEC2010_02.aspx'))return 'interaction-required';
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

String leaveDetailPrepare(String id, int page) =>
    '''
(() => {
 const docs=[];function collect(w){try{docs.push(w.document);for(let i=0;i<w.frames.length;i++)collect(w.frames[i]);}catch(_){}}collect(window);
 for(const d of docs){if(d.location.pathname.endsWith('/SEC2010_04.aspx'))return d.readyState==='complete';}
 for(const d of docs){if(d.location.pathname.endsWith('/SEC4030_01.aspx') && !d.defaultView.eval(${jsonEncode(leavePagePrepare(page))}))return false;}
 const doc=docs.find(d=>d.getElementById('DataGrid'));const table=doc?.getElementById('DataGrid');
 if(!table){for(const d of docs){try{d.defaultView.eval(${jsonEncode(leaveQueryPrepare)});}catch(_){}}return false;}
 const headers=Array.from(table.rows[0].cells,c=>c.textContent.trim());const index=headers.indexOf('假單序號');
 const row=Array.from(table.rows).slice(1).find(r=>r.cells[index]?.textContent.trim()===${jsonEncode(id)});
 const link=row?.querySelector('a[href*="doNewEdit"]');
 if(link && !doc.__niuLeaveDetail){doc.__niuLeaveDetail=true;link.click();}return false;
})()
''';

String leaveInFrames(String script) =>
    '''
(() => {
 function run(w){try {const value=w.eval(${jsonEncode(script)});if(value)return value;for(let i=0;i<w.frames.length;i++){const result=run(w.frames[i]);if(result)return result;}}catch(_){}return null;}
 return run(window);
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
  return JSON.stringify({fields,periods});
 }return null;
})()
''';
