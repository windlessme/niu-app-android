import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:niu_mobile/features/schedule/schedule_screen.dart';
import 'package:niu_mobile/core/web/academic_portal_scripts.dart';
import 'package:niu_mobile/features/graduation/graduation_screen.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Android WebView extracts school fixture and has visible bounds', (
    tester,
  ) async {
    final loaded = Completer<InAppWebViewController>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox.expand(
            child: InAppWebView(
              initialData: InAppWebViewInitialData(
                baseUrl: WebUri(
                  'https://acade.niu.edu.tw/NIU/Application/TKE/TKE22/TKE2240_01.aspx',
                ),
                data: '''<!doctype html><html><body>
        <input type="button" id="QUERY_BTN3" onclick="document.getElementById('table2').innerHTML += '<tr><td>2</td><td>09:10</td><td></td></tr>'">
        <table id="table2"><tr><th>節次</th><th>時間</th><th>星期二</th></tr>
        <tr><td>1</td><td>08:10~09:00</td><td>教師<br>測試課程<br>A101</td></tr></table>
         <div id="div_B">10 20 30 40</div><div id="CRS_PROG">測試學程</div>
         <input type="hidden" name="captcha-token" value="fixture">
         <input id="captcha" style="display:none">
        </body></html>''',
              ),
              onLoadStop: (controller, _) {
                if (!loaded.isCompleted) loaded.complete(controller);
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final controller = await loaded.future.timeout(const Duration(seconds: 30));
    final bounds = tester.getSize(find.byType(InAppWebView));
    expect(bounds.width, greaterThan(100));
    expect(bounds.height, greaterThan(100));
    await controller.evaluateJavascript(
      source: academicDocumentIdentityScript('fixture'),
    );
    // Submission and first settled observation are not accepted as results.
    for (var i = 0; i < 2; i++) {
      expect(
        await controller.evaluateJavascript(source: scheduleQueryScript),
        isFalse,
      );
    }
    expect(
      await controller.evaluateJavascript(source: scheduleQueryScript),
      isTrue,
    );
    final rows =
        jsonDecode(
              await controller.evaluateJavascript(source: scheduleExtractScript)
                  as String,
            )
            as List;
    expect(rows[1][2], contains('測試課程'));
    final graduation = jsonDecode(
      await controller.evaluateJavascript(source: graduationExtractScript)
          as String,
    );
    expect(graduation['diverseHours'], ['10', '20', '30', '40']);
    expect(
      await controller.evaluateJavascript(source: portalInteractionScript),
      isNull,
    );
    await controller.evaluateJavascript(
      source: "document.getElementById('captcha').style.display = 'block'",
    );
    expect(
      await controller.evaluateJavascript(source: portalInteractionScript),
      'interaction-required',
    );
    final navigation = academicNavigationScript(
      Uri.parse(
        'https://acade.niu.edu.tw/NIU/Application/TKE/TKE22/TKE2240_01.aspx',
      ),
    );
    expect(
      await controller.evaluateJavascript(source: navigation),
      'interaction-required',
    );
    await controller.evaluateJavascript(
      source: "document.getElementById('captcha').style.display = 'none'",
    );
    expect(await controller.evaluateJavascript(source: navigation), 'ready');
    final wakeup = Completer<void>();
    controller.addJavaScriptHandler(
      handlerName: 'academicSnapshot',
      callback: (arguments) {
        expect(arguments, isEmpty);
        if (!wakeup.isCompleted) wakeup.complete();
      },
    );
    await controller.evaluateJavascript(source: academicNavigationWakeupScript);
    await wakeup.future.timeout(const Duration(seconds: 10));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
