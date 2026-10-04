import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:niu_mobile/core/session/campus_session.dart';
import 'package:niu_mobile/core/storage/credential_vault.dart';
import 'package:niu_mobile/features/leave/leave_application_service.dart';
import 'package:niu_mobile/features/leave/leave_application_screen.dart';
import 'package:niu_mobile/shared/shared.dart';
import '../test/features/leave/leave_application_screen_test.dart' show FixtureLeaveGateway;

class _Vault implements CredentialVault {
  @override
  Future<void> clear() async {}
  @override
  Future<String?> read(String key) async => null;
  @override
  Future<void> write(String key, String value) async {}
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Android school form uses one-shot postbacks and native file bridge on synthetic HTML',
    (tester) async {
      final loaded = Completer<InAppWebViewController>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InAppWebView(
              initialData: InAppWebViewInitialData(
                baseUrl: WebUri(
                  'https://acade.niu.edu.tw/NIU/Application/SEC/SEC20/SEC2010_01.aspx',
                ),
                data: _application,
              ),
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                useShouldInterceptRequest: true,
              ),
              shouldInterceptRequest: (_, request) async => WebResourceResponse(
                contentType: 'text/html',
                contentEncoding: 'utf-8',
                data: Uint8List.fromList(
                  utf8.encode(
                    request.url.path == '/NIU/utility/UploadFile_HasUseId.aspx'
                        ? _upload
                        : '',
                  ),
                ),
              ),
              onLoadStop: (web, _) {
                if (!loaded.isCompleted) loaded.complete(web);
              },
            ),
          ),
        ),
      );
      await tester.pump();
      final web = await loaded.future.timeout(const Duration(seconds: 30));
      final session = CampusSession(vault: _Vault())..account = 'b123';
      final service = SchoolLeaveApplication(
        session: session,
        evaluate: (script) => web.evaluateJavascript(source: script),
        isActive: () => true,
      );
      var form = await service.initialize();
      expect(form.choices.map((c) => c.value), ['023', '002']);
      expect(form.extensions, ['pdf']);
      form = await service.changeType(form, '002');
      form = await service.changeDates(
        form,
        DateTime(2026, 10, 1),
        DateTime(2026, 10, 2),
      );
      expect(form.type, '002');
      expect(form.end, '115/10/02');
      form = await service.attach(
        form,
        'fixture.pdf',
        Uint8List.fromList(utf8.encode('%PDF-fixture')),
      );
      expect(form.attachments, ['fixture']);
      expect(await web.evaluateJavascript(source: 'window.submitCount'), 0);
      form = await service.draft(form, '合成測試事由', true);
      expect(form.reason, '合成測試事由');
      expect(form.later, isTrue);
      final result = await service.submit(form);
      expect(result.applicationId, 'fixture-001');
      expect(await web.evaluateJavascript(source: 'window.submitCount'), 1);
      service.dispose();
      session.dispose();
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('native leave form surfaces on Android in both themes', (
    tester,
  ) async {
    var converted = false;
    for (final dark in [false, true]) {
      final session = CampusSession(vault: _Vault())..account = 'b123';
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: dark ? NiuTheme.dark : NiuTheme.light,
          home: LeaveApplicationScreen(
            session: session,
            gateway: FixtureLeaveGateway(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('假別與日期'), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (!converted) {
        await binding.convertFlutterSurfaceToImage();
        converted = true;
      }
      await tester.pump();
      await binding.takeScreenshot('personal-leave-${dark ? 'dark' : 'light'}');
      await tester.pumpWidget(const SizedBox());
      session.dispose();
    }
  });
}

const _application = r'''<!doctype html><html><body>
<span id="M_STNO">B123</span><form id="QUERY" method="post" action="/NIU/Application/SEC/SEC20/SEC2010_01.aspx">
<input id="M_FORM_NO" value="">
<select id="M_HOLIDAY_CODE"><option value="023">事假</option><option value="003">公假</option><option value="002">病假</option></select>
<input id="M_HOLIDAY_DATE_S" value="115/10/01"><input id="M_HOLIDAY_DATE_E" value="115/10/01">
<textarea id="M_APP_ORIGIN" maxlength="1000">fixture</textarea><input id="CheckBox1" type="checkbox">
<input id="SEND_BTN1" type="submit" value="送出"><input id="FLOW_BTN" type="button" value="簽核流程" disabled>
<table><tr><td><span ml="PL_本次請假總節數">本次請假總節數</span></td><td>1</td></tr>
<tr><td><span ml="PL_本次請假日期與節次明細">本次請假日期與節次明細</span><table><tr><th>請假日期</th><th>請假節次</th></tr><tr><td>115/10/01</td><td>第一節</td></tr></table></td></tr></table>
</form>
<iframe src="https://acade.niu.edu.tw/NIU/utility/UploadFile_HasUseId.aspx"></iframe>
<script>
let listeners=[];
const manager={get_isInAsyncPostBack:()=>false,add_endRequest:cb=>listeners.push(cb)};
window.Sys={WebForms:{PageRequestManager:{getInstance:()=>manager}}};
window.__doPostBack=()=>listeners.forEach(cb=>cb());
window.submitCount=0;
document.getElementById('QUERY').addEventListener('submit',e=>{
 e.preventDefault();window.submitCount++;
 document.getElementById('M_FORM_NO').value='fixture-001';
 document.getElementById('FLOW_BTN').disabled=false;listeners.forEach(cb=>cb());
});
</script></body></html>''';

const _upload = r'''<!doctype html><html><body>
<form method="post" action="/NIU/utility/UploadFile_HasUseId.aspx" enctype="multipart/form-data">
<input id="filter" type="hidden" value="PDF"><input id="tmpfile" type="file"><input id="remark" type="text"><input id="attach" type="submit" value="附加">
</form><table id="UploadGrid"><tr><th></th><th>預覽</th><th>說明</th></tr></table>
<script>
// Mirrors the school grid: [delete, 預覽 link, 說明 remark].
document.querySelector('form').addEventListener('submit',e=>{
 e.preventDefault();
 const row=document.getElementById('UploadGrid').insertRow();row.insertCell().textContent='刪';
 const a=document.createElement('a');a.href='#download';a.textContent='預覽';row.insertCell().appendChild(a);
 row.insertCell().textContent=document.getElementById('remark').value;
 document.__niuLeaveRevision.count++;
});
</script></body></html>''';
