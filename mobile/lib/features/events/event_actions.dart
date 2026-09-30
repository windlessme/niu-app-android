import 'dart:async';
import 'dart:convert';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../../core/session/campus_session.dart';
import 'event_login_service.dart';
import 'event_portal.dart';
import 'events_screen.dart';

/// Outcome of one register / save / cancel request.
class EventActionResult {
  const EventActionResult(this.success, this.message, {this.needsWeb = false});
  final bool success;

  /// School text when available, otherwise a short explanation.
  final String message;

  /// The school page needs something the app cannot do (login, new form).
  final bool needsWeb;
}

class EventChoice {
  const EventChoice(this.value, this.label, this.checked);
  final String value, label;
  final bool checked;
}

/// Editable registration fields read from the school's RegData page.
class EventRegistrationForm {
  const EventRegistrationForm({
    required this.tel,
    required this.email,
    required this.memo,
    required this.food,
    required this.proof,
    required this.info,
  });
  final String tel, email, memo;
  final List<EventChoice> food, proof;

  /// Read-only identity rows (身份、班級、學號、姓名) as shown by the school.
  final List<(String, String)> info;

  factory EventRegistrationForm.fromJson(Map<String, dynamic> json) {
    List<EventChoice> choices(Object? raw) => [
      for (final c in (raw as List? ?? const []).whereType<Map>())
        EventChoice('${c['value']}', '${c['label']}', c['checked'] == true),
    ];
    return EventRegistrationForm(
      tel: '${json['tel'] ?? ''}',
      email: '${json['email'] ?? ''}',
      memo: '${json['memo'] ?? ''}',
      food: choices(json['food']),
      proof: choices(json['proof']),
      info: [
        for (final r in (json['info'] as List? ?? const []).whereType<List>())
          if (r.length == 2) ('${r[0]}', '${r[1]}'),
      ],
    );
  }
}

/// Everything the event detail needs from the school; replaceable in tests.
abstract class EventActions {
  Future<EventActionResult> register(CampusEvent event);
  Future<EventRegistrationForm> loadForm(CampusEvent event);
  Future<EventActionResult> save(
    CampusEvent event, {
    required String tel,
    required String email,
    required String memo,
    String? food,
    String? proof,
  });
  Future<EventActionResult> cancel(CampusEvent event);
}

class EventFormUnavailable implements Exception {
  const EventFormUnavailable(this.message);
  final String message;
}

/// Drives the school's own forms in a hidden WebView that shares the event
/// login cookies. Buttons are pressed on the school page, so its anti-forgery
/// token and every field the school expects are submitted unchanged.
class WebEventActions implements EventActions {
  WebEventActions([CampusSession? session])
    : session = session ?? CampusSession.instance;
  final CampusSession session;

  @override
  Future<EventActionResult> register(CampusEvent event) => _run(
    event.actionUri(applied: false),
    submit: eventRegisterScript,
    success: const ['報名成功', '已報名', '完成報名'],
    fallbackSuccess: '學校已收到報名。',
    successMessage: '報名成功',
  );

  @override
  Future<EventRegistrationForm> loadForm(CampusEvent event) async {
    final page = await _EventPage.open(session, event.actionUri(applied: true));
    try {
      final raw = await page.eval(eventFormReadScript);
      final data = raw is String ? jsonDecode(raw) : null;
      if (data is! Map || data['ok'] != true) {
        throw const EventFormUnavailable('學校的報名資料頁面格式不同，請在學校網頁修改。');
      }
      return EventRegistrationForm.fromJson(Map<String, dynamic>.from(data));
    } finally {
      await page.dispose();
    }
  }

  @override
  Future<EventActionResult> save(
    CampusEvent event, {
    required String tel,
    required String email,
    required String memo,
    String? food,
    String? proof,
  }) => _run(
    event.actionUri(applied: true),
    submit: eventFormSaveScript(
      tel: tel,
      email: email,
      memo: memo,
      food: food,
      proof: proof,
    ),
    success: const ['修改成功', '更新成功', '已更新', '儲存成功'],
    successMessage: '已儲存修改',
  );

  @override
  Future<EventActionResult> cancel(CampusEvent event) => _run(
    event.actionUri(applied: true),
    submit: eventCancelScript,
    success: const ['取消成功', '已取消', '報名已取消'],
    successMessage: '已取消報名',
    // The school returns to the list after a successful cancellation.
    successPath: '/mvcteam/act/applyme',
  );

  Future<EventActionResult> _run(
    Uri target, {
    required String submit,
    required List<String> success,
    required String successMessage,
    String? fallbackSuccess,
    String? successPath,
  }) async {
    _EventPage? page;
    try {
      page = await _EventPage.open(session, target);
      final submitted = await page.submit(submit);
      if (submitted == null) {
        return const EventActionResult(
          false,
          '學校頁面上找不到對應的按鈕，請在學校網頁操作。',
          needsWeb: true,
        );
      }
      final text = '${page.alert ?? ''}\n${submitted.text}';
      if (success.any(text.contains) ||
          (successPath != null &&
              submitted.url.path.toLowerCase() == successPath)) {
        return EventActionResult(true, page.alert?.trim() ?? successMessage);
      }
      for (final word in const ['失敗', '錯誤', '額滿', '截止', '不符', '無法']) {
        final line = text
            .split('\n')
            .map((l) => l.trim())
            .firstWhere((l) => l.contains(word), orElse: () => '');
        if (line.isNotEmpty) return EventActionResult(false, line);
      }
      if (fallbackSuccess != null &&
          submitted.url.path.toLowerCase().contains('/regdata/')) {
        return EventActionResult(true, fallbackSuccess);
      }
      return const EventActionResult(
        false,
        '學校沒有回傳明確結果，請同步「我的報名」確認。',
        needsWeb: true,
      );
    } on EventFormUnavailable catch (e) {
      return EventActionResult(false, e.message, needsWeb: true);
    } on TimeoutException {
      return const EventActionResult(
        false,
        '學校系統回應逾時，請同步「我的報名」確認是否已完成。',
        needsWeb: true,
      );
    } catch (_) {
      return const EventActionResult(
        false,
        '無法連上活動報名系統，請稍後再試。',
        needsWeb: true,
      );
    } finally {
      await page?.dispose();
    }
  }
}

class _Submitted {
  const _Submitted(this.url, this.text);
  final Uri url;
  final String text;
}

/// One hidden school page. Alerts and confirmations raised by the school's
/// own scripts are accepted (the student already confirmed in the app) and
/// their text is kept as the result message.
class _EventPage {
  _EventPage._(this.session, this.epoch);
  final CampusSession session;
  final int epoch;
  HeadlessInAppWebView? view;
  InAppWebViewController? web;
  Completer<Uri>? _load;
  String? alert;

  static Future<_EventPage> open(CampusSession session, Uri target) async {
    final page = _EventPage._(session, session.coordinator.epoch);
    final entry = await eventPortalEntry(session, target: target);
    page._load = Completer<Uri>();
    page.view = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(url: WebUri('$entry')),
      initialSettings: InAppWebViewSettings(
        incognito: false,
        sharedCookiesEnabled: true,
        javaScriptEnabled: true,
        useShouldOverrideUrlLoading: true,
        allowFileAccess: false,
        allowContentAccess: false,
        supportMultipleWindows: false,
      ),
      onWebViewCreated: (controller) => page.web = controller,
      shouldOverrideUrlLoading: (_, action) async {
        final uri = Uri.tryParse('${action.request.url}');
        return uri != null && isEventUri(uri)
            ? NavigationActionPolicy.ALLOW
            : NavigationActionPolicy.CANCEL;
      },
      onLoadStop: (_, url) {
        final load = page._load;
        if (url != null && load != null && !load.isCompleted) {
          load.complete(Uri.parse('$url'));
        }
      },
      onReceivedError: (_, request, error) {
        final load = page._load;
        if (request.isForMainFrame == true &&
            load != null &&
            !load.isCompleted) {
          load.completeError(const EventFormUnavailable('無法連上活動報名系統。'));
        }
      },
      onJsAlert: (_, request) async {
        page.alert = request.message;
        return JsAlertResponse(
          handledByClient: true,
          action: JsAlertResponseAction.CONFIRM,
        );
      },
      onJsConfirm: (_, request) async {
        page.alert = request.message;
        return JsConfirmResponse(
          handledByClient: true,
          action: JsConfirmResponseAction.CONFIRM,
        );
      },
    );
    await page.view!.run().timeout(const Duration(seconds: 5));
    try {
      final url = await page._load!.future.timeout(const Duration(seconds: 20));
      session.coordinator.requireCurrent(page.epoch);
      if (url.path.toLowerCase() == '/mvcteam/account/login' ||
          await page.eval(
                "!!document.querySelector('input[type=\"password\"], #loginLink')",
              ) ==
              true) {
        throw const EventFormUnavailable('活動報名系統需要重新登入，請在學校網頁操作一次。');
      }
      if (url.path.toLowerCase() != target.path.toLowerCase()) {
        throw const EventFormUnavailable('學校沒有開啟這個活動的報名頁面。');
      }
      return page;
    } catch (_) {
      await page.dispose();
      rethrow;
    }
  }

  Future<dynamic> eval(String source) async {
    session.coordinator.requireCurrent(epoch);
    return web?.evaluateJavascript(source: source);
  }

  /// Runs a script that presses a school button; waits for the next page.
  /// Returns null when the script found nothing to press.
  Future<_Submitted?> submit(String script) async {
    _load = Completer<Uri>();
    final status = await eval(script);
    if (status != 'submitted') return null;
    final url = await _load!.future.timeout(const Duration(seconds: 20));
    session.coordinator.requireCurrent(epoch);
    final text = await eval("document.body ? document.body.innerText : ''");
    return _Submitted(url, text is String ? text : '');
  }

  Future<void> dispose() async {
    final current = view;
    view = null;
    web = null;
    try {
      await current?.dispose().timeout(const Duration(seconds: 3));
    } catch (_) {}
  }
}

/// Presses the school's own 「我要報名」 button inside its checked form.
const eventRegisterScript = r'''
(() => {
  const forms = Array.from(document.forms).filter(f =>
    f.method.toLowerCase() === 'post' && f.querySelector('input[name="__RequestVerificationToken"]'));
  for (const form of forms) {
    const button = Array.from(form.querySelectorAll('button[type="submit"],input[type="submit"],button:not([type])'))
      .find(b => /報名/.test(b.value || b.textContent || '') && !/取消/.test(b.value || b.textContent || ''));
    if (!button || button.disabled) continue;
    button.click();
    return 'submitted';
  }
  return 'missing';
})()
''';

/// Reads the RegData form (field names as used by the school system).
const eventFormReadScript = r'''
(() => {
  const form = Array.from(document.forms).find(f =>
    f.querySelector('input[name="__RequestVerificationToken"]') && f.querySelector('[name="SignId"]'));
  if (!form) return JSON.stringify({ok:false});
  const val = n => form.querySelector('[name="' + n + '"]')?.value ?? '';
  const clean = v => String(v || '').replace(/\s+/g, ' ').trim();
  const radios = n => Array.from(form.querySelectorAll('input[type="radio"][name="' + n + '"]')).map(r => {
    const label = r.id && form.querySelector('label[for="' + r.id + '"]') || r.closest('label');
    return {value: r.value, label: clean(label?.textContent || r.nextSibling?.textContent || r.value), checked: r.checked};
  });
  const info = [];
  for (const input of form.querySelectorAll('input[readonly],input[disabled]')) {
    if (input.type === 'hidden' || !input.value) continue;
    const label = input.id && form.querySelector('label[for="' + input.id + '"]') ||
      input.closest('.form-group')?.querySelector('label');
    if (label) info.push([clean(label.textContent), clean(input.value)]);
  }
  return JSON.stringify({ok:true, tel: val('SignTEL'), email: val('SignEmail'), memo: val('SignMemo'),
    food: radios('Food'), proof: radios('Proof'), info});
})()
''';

String eventFormSaveScript({
  required String tel,
  required String email,
  required String memo,
  String? food,
  String? proof,
}) =>
    '''
(() => {
  const form = Array.from(document.forms).find(f =>
    f.querySelector('input[name="__RequestVerificationToken"]') && f.querySelector('[name="SignId"]'));
  if (!form) return 'missing';
  const set = (n, v) => { const e = form.querySelector('[name="' + n + '"]'); if (e) e.value = v; };
  set('SignTEL', ${jsonEncode(tel)});
  set('SignEmail', ${jsonEncode(email)});
  set('SignMemo', ${jsonEncode(memo)});
  const pick = (n, v) => { if (v === null) return;
    const r = Array.from(form.querySelectorAll('input[type="radio"][name="' + n + '"]')).find(x => x.value === v);
    if (r) r.checked = true; };
  pick('Food', ${jsonEncode(food)});
  pick('Proof', ${jsonEncode(proof)});
  const button = Array.from(form.querySelectorAll('button[type="submit"],input[type="submit"],button:not([type])'))
    .find(b => /儲存|修改/.test(b.value || b.textContent || ''));
  if (!button || button.disabled) return 'missing';
  button.click();
  return 'submitted';
})()
''';

/// Presses the school's own cancel button on the RegData page.
const eventCancelScript = r'''
(() => {
  const forms = Array.from(document.forms).filter(f =>
    f.querySelector('input[name="__RequestVerificationToken"]') && f.querySelector('[name="SignId"]'));
  for (const form of forms) {
    const button = Array.from(form.querySelectorAll('button[type="submit"],input[type="submit"],button:not([type])'))
      .find(b => /取消/.test(b.value || b.textContent || ''));
    if (!button || button.disabled) continue;
    button.click();
    return 'submitted';
  }
  return 'missing';
})()
''';
