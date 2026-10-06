import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/core/session/campus_session.dart';
import 'package:niu_mobile/features/leave/leave_repository.dart';
import 'package:niu_mobile/features/leave/leave_screen.dart';
import 'package:niu_mobile/features/leave/leave_widgets.dart';
import 'package:niu_mobile/shared/shared.dart';
import '../../support/fakes.dart';

void main() {
  test(
    'detail workflow waits for the existing frame and retains captured detail',
    () {
      final result = Process.runSync('node', [
        '-e',
        '''
const assert=require('node:assert/strict');
const script=${jsonEncode(leaveDetailWithWorkflowExtract())};
global.window={frames:[],eval:()=>null};
assert.equal(eval(script),null);
window.__niuLeaveWorkflowDetail={fields:{'請假事由':'fixture'},periods:[]};
assert.equal(eval(script),null);
window.frames=[{frames:[],eval:()=>JSON.stringify({workflow:[{'簽核狀況':'待簽核'}]})}];
const value=JSON.parse(eval(script));
assert.equal(value.fields['請假事由'],'fixture');
assert.equal(value.workflow[0]['簽核狀況'],'待簽核');
window.__niuLeaveWorkflowUnavailable=true;
assert.equal(JSON.parse(eval(script)).workflow,undefined);
''',
      ]);
      expect(result.exitCode, 0, reason: result.stderr.toString());
    },
  );
  test('detail search pages through results and clicks the matching row', () {
    final result = Process.runSync('node', [
      '-e',
      '''
const assert=require('node:assert/strict');
const clicks=[];const storage={};
function makeList(pages){
  const input={value:'1'};let page=1;
  const rowsFor=p=>[
    ['假單序號','請假類別','審核結果'],
    ...pages[p-1].map(([id,link])=>[id,'病假','已核准',link]),
  ];
  const cell=t=>({textContent:t});
  const table={get rows(){return rowsFor(page).map(r=>({
    cells:r.slice(0,3).map(cell),
    querySelector:sel=>{const link=r[3];if(!link)return null;
      if(link==='doNewEdit'&&sel.includes('doNewEdit'))return {click:()=>clicks.push(r[0])};
      if(link==='onclick'&&!sel.includes('doNewEdit')&&sel.includes('onclick'))return {click:()=>clicks.push(r[0])};
      return null;},
  }));}};
  const view={
    eval:()=>true,
    sessionStorage:{getItem:k=>storage[k]??null,setItem:(k,v)=>{storage[k]=v;}},
    __niuAcademicRun:'run-1',
  };
  const doc={
    location:{pathname:'/NIU/Application/SEC/SEC40/SEC4030_01.aspx'},
    readyState:'complete',defaultView:view,
    getElementById:id=>({DataGrid:table,PC_PageNo:input,PC_TotalPage:{textContent:String(pages.length)},
      PC_ToGo:{click:()=>{page=parseInt(input.value,10);}}})[id]??null,
  };
  return {doc,input};
}
function run(script,doc){global.window={document:doc,frames:[]};return eval(script);}
// The record moved from page 1 (where it was cached) to page 2, with an onclick link.
const {doc}=makeList([[['A1','doNewEdit']],[['B2','onclick']]]);
const script=${jsonEncode(leaveDetailPrepare('B2', 1))};
global.window={document:doc,frames:[]};
for(let i=0;i<4;i++)assert.equal(eval(script),false);
assert.deepEqual(clicks,['B2']);
// A row that exists nowhere does not click anything or loop forever.
clicks.length=0;
const other=makeList([[['A1','doNewEdit']]]);
global.window={document:other.doc,frames:[]};
const missing=${jsonEncode(leaveDetailPrepare('ZZ', 1))};
for(let i=0;i<3;i++)assert.equal(eval(missing),false);
assert.deepEqual(clicks,[]);
''',
    ]);
    expect(result.exitCode, 0, reason: result.stderr.toString());
  });

  test('individual leave detail page opens its workflow like group leaves', () {
    final result = Process.runSync('node', [
      '-e',
      '''
const assert=require('node:assert/strict');
for(const page of ['SEC2010_01','SEC2010_04']){
  let flow=0;
  const hidden={H_FORM_CODE:'F',H_APPROVE_FLOW_CODE:'A',H_GROUP_APPLY_NO:page==='SEC2010_04'?'G':'',M_FORM_NO:'N'};
  const doc={
    location:{pathname:'/NIU/Application/SEC/SEC20/'+page+'.aspx',href:'https://acade.niu.edu.tw/NIU/Application/SEC/SEC20/'+page+'.aspx'},
    readyState:'complete',
    querySelectorAll:()=>[],
    getElementById:id=>id==='FLOW_BTN'?{disabled:false,click:()=>flow++}:(id in hidden?{value:hidden[id]}:null),
  };
  global.window={document:doc,frames:[]};
  const script=${jsonEncode(leaveDetailPrepare('N', 1))};
  assert.equal(eval(script),false);
  assert.equal(flow,1);
  assert.ok(window.__niuLeaveWorkflowDetail);
  assert.equal(new URL(window.__niuLeaveWorkflowDetail.workflowUrl).pathname,
    page==='SEC2010_01'?'/NIU/Application/FLO/FLO30/FLO3020_01.aspx':'/NIU/Application/FLO/FLO30/FLO3040_01.aspx');
  assert.equal(eval(script),true);
}
''',
    ]);
    expect(result.exitCode, 0, reason: result.stderr.toString());
  });

  test('workflow accepts only the school read-only endpoint', () {
    expect(
      isLeaveWorkflowUri(
        Uri.parse(
          'https://acade.niu.edu.tw/NIU/Application/FLO/FLO30/FLO3040_01.aspx?FORM_CODE=fixture',
        ),
      ),
      isTrue,
    );
    // Individual (non-group) leaves use the FORM_NO based flow page.
    expect(
      isLeaveWorkflowUri(
        Uri.parse(
          'https://acade.niu.edu.tw/NIU/Application/FLO/FLO30/FLO3020_01.aspx?FORM_NO=fixture',
        ),
      ),
      isTrue,
    );
    expect(
      isLeaveWorkflowUri(
        Uri.parse(
          'https://evil.test/NIU/Application/FLO/FLO30/FLO3040_01.aspx',
        ),
      ),
      isFalse,
    );
    expect(
      isLeaveWorkflowUri(
        Uri.parse(
          'https://acade.niu.edu.tw/NIU/Application/FLO/FLO00/FLO0030_01.aspx',
        ),
      ),
      isFalse,
    );
  });
  test('workflow extraction preserves school order and raw status', () {
    final result = Process.runSync('node', [
      '-e',
      '''
const assert=require('node:assert/strict');
global.location={hostname:'acade.niu.edu.tw',pathname:'/NIU/Application/FLO/FLO30/FLO3040_01.aspx'};
const grid=r=>r.map(row=>({cells:row.map(textContent=>({textContent}))}));
let rows=grid([['簽核狀況','簽核日期','關卡說明','簽核單位'],['結案','2026/09/30','第一關','單位甲'],['待簽核','','第二關','單位乙']]);
let tds=[];
global.document={getElementById:()=>({rows}),querySelectorAll:()=>tds};
const result=JSON.parse(eval(${jsonEncode(leaveWorkflowExtract)}));
assert.equal(result.workflow.length,2);assert.equal(result.workflow[0]['簽核狀況'],'結案');assert.equal(result.workflow[1]['簽核日期'],'');
assert.equal('簽核人' in result.workflow[0],false);assert.equal(result.workflowName,'');
// Pages that list the signer and comment, plus the flow name, keep them.
rows=grid([['簽核狀況','簽核日期','關卡說明','簽核單位','簽核人','簽核意見'],['退回','2026/10/01','導師','資工系','王大明','請補  證明']]);
tds=[{textContent:'簽核流程：'},{textContent:'12- 學生請假'}];
const full=JSON.parse(eval(${jsonEncode(leaveWorkflowExtract)}));
assert.equal(full.workflow[0]['簽核人'],'王大明');assert.equal(full.workflow[0]['簽核意見'],'請補 證明');assert.equal(full.workflowName,'學生請假');
location.pathname='/NIU/Application/FLO/FLO30/FLO3020_01.aspx';assert.equal(JSON.parse(eval(${jsonEncode(leaveWorkflowExtract)})).workflow.length,1);
location.pathname='/NIU/Application/FLO/FLO00/FLO0030_01.aspx';assert.equal(eval(${jsonEncode(leaveWorkflowExtract)}),null);
''',
    ]);
    expect(result.exitCode, 0, reason: result.stderr.toString());
  });
  test('statistics agrees once; application still requires interaction', () {
    final result = Process.runSync('node', [
      '-e',
      '''
const assert=require('node:assert/strict');let clicks=0;
const button={value:'同意',disabled:false,click:()=>clicks++};
const doc={location:{href:'https://acade.niu.edu.tw/NIU/Application/SEC/SEC20/SEC2010_02.aspx'},getElementById:()=>button};
global.window={document:doc,frames:[]};
assert.equal(eval(${jsonEncode(leaveMenuNavigation(true))}), 'interaction-required');
assert.equal(clicks,0);
const script=${jsonEncode(leaveMenuNavigation(true, agreeForStatistics: true))};
assert.equal(eval(script),null);eval(script);assert.equal(clicks,1);
''',
    ]);
    expect(result.exitCode, 0, reason: result.stderr.toString());
  });
  for (final dark in [false, true]) {
    testWidgets(
      'long leave categories shorten with semantic counts dark=$dark',
      (tester) async {
        tester.view.physicalSize = const Size(320, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final semantics = tester.ensureSemantics();
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? NiuTheme.dark : NiuTheme.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: const Scaffold(
              body: SingleChildScrollView(
                child: Padding(
                  padding: EdgeInsets.all(NiuSpacing.xl),
                  child: LeaveTypeStatistics(
                    periods: {'公假': '1', '產假（產前假／陪產假／流產假／哺乳假）': '0', '病假': '0'},
                  ),
                ),
              ),
            ),
          ),
        );
        expect(find.bySemanticsLabel('公假 1 節'), findsOneWidget);
        // Zero types share one quiet line, named without their sub-types.
        expect(find.text('產假、病假：0 節'), findsOneWidget);
        expect(find.textContaining('產前假'), findsNothing);
        expect(tester.takeException(), isNull);
        semantics.dispose();
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  final snapshots = <String, dynamic>{
    'statistics': {
      'updatedAt': '2026-09-29T00:00:00Z',
      'data': {
        'periods': {'事假': '12', '公假': '1'},
        'scope': '本學期',
      },
    },
  };
  test('private leave cache enforces owner and logout epoch', () async {
    final vault = MemoryVault();
    final session = CampusSession(vault: vault, platformCleanup: [])
      ..account = 'b123';
    final repository = LeaveRepository(session);
    await repository.save(snapshots, 0, 'b123');
    expect(await repository.restore(), snapshots);
    session.account = 'b456';
    expect(await repository.restore(), isEmpty);
    await expectLater(repository.save(snapshots, 0, 'b123'), throwsStateError);
    await session.logout();
    expect(vault.values['leaveCache'], isNull);
    await repository.dispose();
    session.dispose();
  });
  test('malformed leave cache rejected', () {
    expect(
      () => LeaveRepository.validate({
        'statistics': {'data': {}},
      }),
      throwsFormatException,
    );
  });
  for (final dark in [false, true]) {
    for (final inset in [24.0, 48.0]) {
      testWidgets('pagination clears system inset $inset dark=$dark', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final vault = MemoryVault()
          ..values['leaveCache'] = jsonEncode({
            'version': 1,
            'account': 'b123',
            'snapshots': {
              ...snapshots,
              'list': {
                'updatedAt': '2026-09-29T00:00:00Z',
                'data': {
                  'records': [],
                  'page': '1',
                  'pages': '1',
                  'total': '0',
                },
              },
            },
          });
        final session = CampusSession(vault: vault)..account = 'b123';
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? NiuTheme.dark : NiuTheme.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(2),
                padding: EdgeInsets.zero,
                viewPadding: EdgeInsets.only(bottom: inset),
                systemGestureInsets: EdgeInsets.only(bottom: inset),
              ),
              child: child!,
            ),
            home: LeaveScreen(session: session),
          ),
        );
        await tester.pumpAndSettle();
        final scroll = find.byType(Scrollable).first;
        await tester.scrollUntilVisible(
          find.text('更新紀錄'),
          100,
          scrollable: scroll,
        );
        // A single page needs no pager.
        expect(find.text('上一頁'), findsNothing);
        expect(find.text('下一頁'), findsNothing);
        final position = tester.state<ScrollableState>(scroll).position;
        position.jumpTo(position.maxScrollExtent);
        await tester.pump();
        final last = find.widgetWithText(TextButton, '更新紀錄');
        expect(
          tester.getBottomRight(last).dy,
          lessThanOrEqualTo(568 - inset - NiuSpacing.xxl),
        );
        expect(tester.getSize(last).height, greaterThanOrEqualTo(48));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        session.dispose();
      });
    }
    testWidgets('cached leave dashboard fits small screen dark=$dark', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final vault = MemoryVault()
        ..values['leaveCache'] = jsonEncode({
          'version': 1,
          'account': 'b123',
          'snapshots': snapshots,
        });
      final session = CampusSession(vault: vault)..account = 'b123';
      await tester.pumpWidget(
        MaterialApp(
          theme: dark ? NiuTheme.dark : NiuTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: LeaveScreen(session: session),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('13 節'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('請假紀錄'), 100);
      expect(
        find.byWidgetPredicate((w) => w is NiuSection && w.title == '請假紀錄'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    });
  }

  testWidgets('one refresh reads totals, records and actions together', (
    tester,
  ) async {
    final session = CampusSession(vault: MemoryVault(), platformCleanup: []);
    await session.enterDemo();
    addTearDown(session.dispose);
    var reads = 0;
    final observer = _PushCounter(() => reads++);
    await tester.pumpWidget(
      MaterialApp(
        theme: NiuTheme.light,
        navigatorObservers: [observer],
        home: LeaveScreen(session: session),
      ),
    );
    await tester.pumpAndSettle();
    // First visit with no cache reads all three parts.
    expect(reads, 3);
    expect(find.text('事假'), findsWidgets);

    // A single control, not one per section.
    expect(find.byTooltip('更新請假資料'), findsOneWidget);
    expect(find.byTooltip('更新統計'), findsNothing);
    expect(find.widgetWithText(TextButton, '更新'), findsNothing);

    await tester.tap(find.byTooltip('更新請假資料'));
    await tester.pumpAndSettle();
    expect(reads, 6);
  });
  test('type names drop their parenthesised sub-types', () {
    expect(leaveTypeShortName('產假（產前假／陪產假／流產假／哺乳假）'), '產假');
    expect(leaveTypeShortName('產假(產前假/陪產假/流產假)'), '產假');
    expect(leaveTypeShortName('事假'), '事假');
    expect(leaveTypeShortName('（其他）'), '（其他）');
  });
  testWidgets('used types fill every row with equal, aligned tiles', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: NiuTheme.light,
        home: const Scaffold(
          body: Padding(
            padding: EdgeInsets.all(NiuSpacing.xl),
            child: LeaveTypeStatistics(
              periods: {
                '事假': '2',
                '病假': '12',
                '公假': '1',
                '產假（產前假／陪產假／流產假／哺乳假）': '4',
                '喪假': '3',
                '婚假': '0',
              },
            ),
          ),
        ),
      ),
    );
    final tiles = find.byType(NiuWell);
    expect(tiles, findsNWidgets(5));
    final rects = [for (var i = 0; i < 5; i++) tester.getRect(tiles.at(i))];
    // Three on the first row, two stretched across the second.
    expect(rects[0].top, rects[2].top);
    expect(rects[3].top, rects[4].top);
    expect(rects[3].top, greaterThan(rects[0].bottom));
    expect(rects[3].left, rects[0].left);
    expect(rects[4].right, closeTo(rects[2].right, 0.5));
    for (final r in rects.skip(1).take(2)) {
      expect(r.height, rects[0].height);
    }
    expect(rects[4].height, rects[3].height);
    expect(find.text('產假'), findsOneWidget);
    expect(find.text('婚假：0 節'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('workflow names the signer and shows why it was returned', (
    tester,
  ) async {
    final steps = [
      {
        '簽核狀況': '已簽核',
        '簽核日期': '115/10/01',
        '關卡說明': '申請人',
        '簽核單位': '資工系',
        '簽核人': '陳宜安',
        '簽核意見': '(申請送出)',
      },
      {
        '簽核狀況': '退回',
        '簽核日期': '115/10/02',
        '關卡說明': '導師',
        '簽核單位': '資工系',
        '簽核人': '王大明',
        '簽核意見': '請補證明',
      },
    ];
    expect(LeaveApprovalStep.returnReason(steps), '請補證明');
    await tester.pumpWidget(
      MaterialApp(
        theme: NiuTheme.light,
        home: Scaffold(body: LeaveWorkflow(steps: steps)),
      ),
    );
    expect(find.text('資工系 王大明'), findsOneWidget);
    expect(find.text('退回'), findsOneWidget);
    expect(find.text('請補證明'), findsOneWidget);
    // Automatic school notes add nothing and stay hidden.
    expect(find.text('(申請送出)'), findsNothing);
  });
}

class _PushCounter extends NavigatorObserver {
  _PushCounter(this.onPush);
  final VoidCallback onPush;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute != null) onPush();
  }
}
