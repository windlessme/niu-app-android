import 'dart:convert';

/// Which school form a leave screen works on: a new application, or an
/// existing one opened from 學生請假修改 (SEC2015) to change or to add proof.
class LeaveEntry {
  const LeaveEntry._(this.formNo, this.mode);
  static const apply = LeaveEntry._(null, null);
  const LeaveEntry.modify(String formNo) : this._(formNo, 'MOD');
  const LeaveEntry.supplement(String formNo) : this._(formNo, 'DETAIL');

  /// The existing form, or null for a new application.
  final String? formNo;

  /// The school's hidden `Mode` on that form: `MOD` or `DETAIL`.
  final String? mode;
  bool get isApply => formNo == null;
  bool get isModify => mode == 'MOD';
  bool get isSupplement => mode == 'DETAIL';

  /// The school's own label on the form's submit button.
  String get submitLabel => isModify ? '修改' : '送出';
  String get title => isModify
      ? '修改假單'
      : isSupplement
      ? '補交證明文件'
      : '申請請假';
}

/// What 學生請假修改 currently allows for one form. The school decides, per
/// form and per approval state; nothing here is inferred from the status text.
class LeaveActions {
  const LeaveActions({
    required this.formNo,
    this.withdraw = false,
    this.modify = false,
    this.supplement = false,
  });
  final String formNo;
  final bool withdraw, modify, supplement;
  bool get any => withdraw || modify || supplement;

  static List<LeaveActions> fromSnapshot(Object? data) => [
    if (data is Map && data['actions'] is List)
      for (final a in (data['actions'] as List).whereType<Map>())
        if ('${a['formNo'] ?? ''}'.isNotEmpty)
          LeaveActions(
            formNo: '${a['formNo']}',
            withdraw: a['withdraw'] == true,
            modify: a['modify'] == true,
            supplement: a['supplement'] == true,
          ),
  ];
}

const leaveManagePath =
    '/NIU/Application/SEC/SEC20/SEC2015_.aspx?progcd=SEC2015';

/// 請假紀錄 (SEC4030): every form with its approval state.
const leaveRecordsPath =
    '/NIU/Application/SEC/SEC40/SEC4030_.aspx?progcd=SEC4030';

/// A school list page and the file its grid lives in.
typedef LeaveListPage = ({String path, String file});
const leaveManageList = (path: leaveManagePath, file: 'SEC2015_01');
const leaveRecordsList = (path: leaveRecordsPath, file: 'SEC4030_01');

/// Shared by every script below: the frames of the school's MainFrame, and
/// the list page's rows keyed by header text.
String _helpers(LeaveListPage page) =>
    ' const listFile=${jsonEncode(page.file)};\n$_leaveListHelpers';

const _leaveListHelpers = r'''
 const docs=[];function collect(w){try{docs.push(w.document);for(let i=0;i<w.frames.length;i++)collect(w.frames[i]);}catch(_){}}collect(window);
 const path=d=>{try{return new URL(d.location.href).pathname;}catch(_){return '';}};
 const expired=()=>docs.some(d=>/\/(?:timeoutpage|logout)\.aspx$/i.test(path(d)));
 // A page replaced by [leaveListReset] stays visible until the new one commits.
 const list=()=>docs.find(d=>path(d).toLowerCase().endsWith('/'+listFile.toLowerCase()+'.aspx')&&!d.__niuLeaveManageStale);
 const cellText=c=>String((c&&c.innerText)||'').replace(/\s+/g,' ').trim();
 // The school writes the same date as 115/10/08 or 1151008.
 const roc=v=>{const m=String(v||'').trim().match(/^(\d{2,3})\/?(\d{2})\/?(\d{2})$/);return m?m[1].padStart(3,'0')+'/'+m[2]+'/'+m[3]:String(v||'').trim();};
 function rows(d){
   const grid=d.getElementById('DataGrid');if(!grid||!grid.rows.length)return [];
   const head=Array.from(grid.rows[0].cells,cellText);
   return Array.from(grid.rows).filter(r=>!r.querySelector('th')).map(r=>({row:r,get:name=>{const i=head.indexOf(name);return i<0?'':cellText(r.cells[i]);}}));
 }
''';

/// Opens a school list in mainFrame the way the school's menu does
/// (`top.mainFrame.location.href = url; top.hideView()`), runs its「查詢」
/// once and answers 'ready' when the list has settled. Callers poll it.
String leaveListNavigation(LeaveListPage page) =>
    '''
(() => {
${_helpers(page)}
 if(expired())return 'session-expired';
 const main=window.frames['mainFrame'];
 if(!main)return null;
 const opened='__niuLeaveOpened:'+listFile;
 const d=list();
 if(!d){
   // MainFrame's own scripts can drop or replace the navigation: send it
   // again, at most twice, once mainFrame has stayed on its old page for
   // 10 s or moved somewhere else for 4 s.
   const sent=window[opened];
   const waited=sent&&Date.now()-sent.at;
   const stuck=sent&&sent.count<3&&(main.document===sent.previous?waited>10000:waited>4000);
   if(!sent||stuck){
     window[opened]={at:Date.now(),count:(sent?sent.count:0)+1,previous:main.document};
     main.location.href=${jsonEncode(page.path)};
     try{if(typeof window.hideView==='function')window.hideView();}catch(_){}
   }
   return null;
 }
 if(d.readyState!=='complete')return null;
 if(!d.__niuLeaveManageQueried){
   const button=d.getElementById('QUERY_BTN1');if(!button||button.disabled)return null;
   d.__niuLeaveManageQueried=Date.now();button.click();return null;
 }
 const manager=d.defaultView.Sys?.WebForms?.PageRequestManager?.getInstance();
 if(manager?.get_isInAsyncPostBack()||d.querySelector('.blockUI'))return null;
 // Before a query the pager reads「共 頁」; afterwards it has a page count.
 const pager=((d.body.innerText||'').match(/【[^】]*】/)||[''])[0];
 if(!/共\\s*\\d+\\s*頁/.test(pager)&&Date.now()-d.__niuLeaveManageQueried<6000)return null;
 return 'ready';
})()
''';

/// 學生請假修改, the list that offers 撤回、修改 and 補檔.
final leaveManageNavigation = leaveListNavigation(leaveManageList);

/// The actions each listed form allows: 撤回 is the row's delete link,
/// 修改 and 補檔 are cells that open the form as `Mod` or `Detail`.
final leaveManageExtract =
    '''
(() => {
${_helpers(leaveManageList)}
 const d=list();if(!d||!d.getElementById('DataGrid'))return null;
 const actions=rows(d).map(r=>{
   const clicks=Array.from(r.row.cells,c=>c.getAttribute('onclick')||'');
   return {formNo:r.get('假單序號'),withdraw:!!r.row.querySelector('a[id\$="_del"]'),
     modify:clicks.some(c=>/doEdit1_2\\(.*'Mod'\\)/.test(c)),supplement:clicks.some(c=>/doEdit1_2\\(.*'Detail'\\)/.test(c))};
 }).filter(a=>a.formNo&&(a.withdraw||a.modify||a.supplement));
 return JSON.stringify({actions});
})()
''';

/// Taps the listed form's `Mod` or `Detail` cell, which posts it into
/// viewFrame as SEC2010_01.aspx. Answers 'opened' or 'missing'.
String leaveManageOpen(String formNo, String mode) =>
    '''
(() => {
${_helpers(leaveManageList)}
 const formNo=${jsonEncode(formNo)}, cell=${jsonEncode(mode == 'MOD' ? 'Mod' : 'Detail')};
 const d=list();if(!d)return 'missing';
 const row=rows(d).find(r=>r.get('假單序號')===formNo);
 const target=row&&Array.from(row.row.cells).find(c=>(c.getAttribute('onclick')||'').includes("'"+cell+"'"));
 if(!target)return 'missing';
 if(window.__niuLeaveManageClicked!==formNo+cell){window.__niuLeaveManageClicked=formNo+cell;target.click();}
 return 'opened';
})()
''';

/// Does what the row's「撤回」link does: `onclick="return doDelete();"` (the
/// school's「確定刪除 1 筆資料??」confirm), then its `__doPostBack`. Both run
/// from timers so the confirm never blocks this call; the postback is a string
/// timer because MS Ajax inspects its caller and fails from strict code.
/// Answers 'scheduled', 'missing' or 'changed'; [leaveWithdrawState] follows.
String leaveWithdraw(String formNo) =>
    '''
(() => {
${_helpers(leaveManageList)}
 const formNo=${jsonEncode(formNo)};
 if(expired())return 'expired';
 const d=list();if(!d)return 'missing';
 const w=d.defaultView;
 const row=rows(d).find(r=>r.get('假單序號')===formNo);
 const link=row&&row.row.querySelector('a[id\$="_del"]');
 if(!link)return 'missing';
 const target=((link.getAttribute('href')||'').match(/__doPostBack\\('([^']+)'/)||[])[1];
 if(!target||!/^DataGrid\\\$ctl\\d+\\\$del\$/.test(target)||typeof w.doDelete!=='function')return 'changed';
 if(window.__niuLeaveWithdraw)return 'changed';
 window.__niuLeaveWithdraw={formNo,state:'confirming',doc:d};
 w.setTimeout(()=>{
   if(!w.doDelete()){window.__niuLeaveWithdraw.state='declined';return;}
   window.__niuLeaveWithdraw.state='posted';
   w.setTimeout("__doPostBack('"+target+"','')",0);
 },0);
 return 'scheduled';
})()
''';

/// Where the withdraw stands: 'confirming', 'declined', 'waiting' while the
/// postback runs, then 'reloaded' or 'removed' once the list has changed.
final leaveWithdrawState =
    '''
(() => {
${_helpers(leaveManageList)}
 const job=window.__niuLeaveWithdraw;if(!job)return 'none';
 if(expired())return 'expired';
 if(job.state!=='posted')return job.state;
 const d=list();
 if(!d||d!==job.doc)return 'reloaded';
 if(d.querySelector('.blockUI'))return 'waiting';
 const manager=d.defaultView.Sys?.WebForms?.PageRequestManager?.getInstance();
 if(manager?.get_isInAsyncPostBack())return 'waiting';
 return rows(d).some(r=>r.get('假單序號')===job.formNo)?'waiting':'removed';
})()
''';

/// Opens a list afresh for a check after a change. The current page is
/// marked stale so it is never read as the new one.
String leaveListReset(LeaveListPage page) =>
    '''
(() => {
${_helpers(page)}
 const old=list();if(old)old.__niuLeaveManageStale=true;
 window.__niuLeaveWithdraw=null;window.__niuLeaveManageClicked=null;
 const main=window.frames['mainFrame'];if(!main)return false;
 window['__niuLeaveOpened:'+listFile]={at:Date.now(),count:1,previous:main.document};
 main.location.href=${jsonEncode(page.path)};
 return true;
})()
''';

final leaveManageReset = leaveListReset(leaveManageList);

/// Where [formNo] stands on the settled 學生請假修改 list: 'gone',
/// 'locked' (still listed, no longer withdrawable) or 'listed'.
String leaveManageListed(String formNo) =>
    '''
(() => {
${_helpers(leaveManageList)}
 const d=list();if(!d)return null;
 const row=rows(d).find(r=>r.get('假單序號')===${jsonEncode(formNo)});
 if(!row)return 'gone';
 return row.row.querySelector('a[id\$="_del"]')?'listed':'locked';
})()
''';

/// 請假紀錄 rows, dates as 115/10/08, for checking what a submit did.
final leaveRecordRows =
    '''
(() => {
${_helpers(leaveRecordsList)}
 const d=list();if(!d||!d.getElementById('DataGrid'))return null;
 return JSON.stringify(rows(d).map(r=>({formNo:r.get('假單序號'),applied:roc(r.get('申請日期')),
   type:r.get('請假類別'),start:roc(r.get('請假起日')),end:roc(r.get('請假訖日')),status:r.get('審核結果')})).filter(r=>r.formNo));
})()
''';
