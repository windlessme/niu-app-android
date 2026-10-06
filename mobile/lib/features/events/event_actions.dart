import 'dart:async';
import 'dart:convert';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../../core/session/campus_session.dart';
import 'event_login_service.dart';
import 'event_portal.dart';
import 'events_screen.dart';
import 'event_models.dart';

/// Outcome of one register / save / cancel request.
class EventActionResult {
  const EventActionResult(
    this.success,
    this.message, {
    this.needsWeb = false,
    this.uncertain = false,
  });
  final bool success;

  /// The request may have reached the school without a readable reply.
  /// Such an action must not be sent again before 「我的報名」 is checked.
  final bool uncertain;

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

  /// The student's 「我的報名」 list, read without showing the school page.
  Future<List<CampusEvent>> registrations();

  /// 可報名活動, read without showing the school page.
  Future<List<CampusEvent>> available();
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
    event: event,
    expectRegistered: true,
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
    // Authoritative: reopen the registration and compare what was saved.
    verify: (page) async {
      await page.go(event.actionUri(applied: true));
      final raw = await page.eval(eventFormReadScript);
      final data = raw is String ? jsonDecode(raw) : null;
      if (data is! Map || data['ok'] != true) return null;
      final form = EventRegistrationForm.fromJson(
        Map<String, dynamic>.from(data),
      );
      String? checked(List<EventChoice> c) =>
          c.where((x) => x.checked).firstOrNull?.value;
      return form.tel.trim() == tel.trim() &&
          form.email.trim() == email.trim() &&
          form.memo.trim() == memo.trim() &&
          (food == null || checked(form.food) == food) &&
          (proof == null || checked(form.proof) == proof);
    },
  );

  @override
  Future<EventActionResult> cancel(CampusEvent event) => _run(
    event.actionUri(applied: true),
    event: event,
    expectRegistered: false,
    submit: eventCancelScript,
    success: const ['取消成功', '已取消', '報名已取消'],
    successMessage: '已取消報名',
    // As on iOS: after cancelling, the school leaves RegData for a list page.
    leftRegData: true,
  );

  @override
  Future<List<CampusEvent>> registrations() => _list(eventVerificationUri);

  @override
  Future<List<CampusEvent>> available() =>
      _list(Uri.parse('https://ccsys.niu.edu.tw/MvcTeam/Act'));

  Future<List<CampusEvent>> _list(Uri target) async {
    final page = await _EventPage.open(session, target);
    try {
      final raw = await page.eval(eventsExtractScript);
      if (raw is! String) throw const EventFormUnavailable('無法讀取我的報名');
      return [
        for (final e in (jsonDecode(raw) as List).whereType<Map>())
          CampusEvent.fromJson(Map<String, dynamic>.from(e)),
      ];
    } finally {
      await page.dispose();
    }
  }

  Future<EventActionResult> _run(
    Uri target, {
    required String submit,
    required List<String> success,
    required String successMessage,
    String? fallbackSuccess,
    bool leftRegData = false,
    CampusEvent? event,
    bool? expectRegistered,
    Future<bool?> Function(_EventPage page)? verify,
  }) async {
    _EventPage? page;
    try {
      page = await _EventPage.open(session, target);
      final submitted = await page.submit(submit);
      if (submitted == null) {
        // No button because the student is already registered?
        if (event != null && expectRegistered == true) {
          try {
            if (await page.isListed(event) == true) {
              return const EventActionResult(true, '你已經報名過這個活動。');
            }
          } catch (_) {}
        }
        return const EventActionResult(
          false,
          '學校頁面上找不到對應的按鈕，請在學校網頁操作。',
          needsWeb: true,
        );
      }
      final text = '${page.alert ?? ''}\n${submitted.text}';
      // The authoritative answer is the student's own 「我的報名」 list.
      if (event != null && expectRegistered != null) {
        bool? listed;
        try {
          listed = await page.isListed(event);
        } catch (_) {
          listed = null; // Fall back to the school's own reply below.
        }
        if (listed == expectRegistered) {
          return EventActionResult(true, successMessage);
        }
      }
      if (verify != null) {
        bool? verified;
        try {
          verified = await verify(page);
        } catch (_) {
          verified = null; // Fall back to the school's own reply below.
        }
        if (verified == true) return EventActionResult(true, successMessage);
      }
      if (success.any(text.contains) ||
          (leftRegData &&
              submitted.url.path.toLowerCase().startsWith('/mvcteam/act') &&
              !submitted.url.path.toLowerCase().contains('/regdata/'))) {
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
        uncertain: true,
      );
    } on EventFormUnavailable catch (e) {
      return EventActionResult(false, e.message, needsWeb: true);
    } on TimeoutException {
      return const EventActionResult(
        false,
        '學校系統回應逾時，請同步「我的報名」確認是否已完成。',
        needsWeb: true,
        uncertain: true,
      );
    } catch (_) {
      return const EventActionResult(
        false,
        '無法連上活動報名系統，請稍後再試。',
        needsWeb: true,
        uncertain: true,
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
    // Only an explicit "missing" means nothing was pressed. Anything else
    // (including a reply lost to navigation) waits for the school's page.
    if (status == 'missing') return null;
    final url = await _load!.future.timeout(const Duration(seconds: 20));
    session.coordinator.requireCurrent(epoch);
    final text = await eval("document.body ? document.body.innerText : ''");
    return _Submitted(url, text is String ? text : '');
  }

  /// Whether [event] appears in 「我的報名」; null when the list is unreadable.
  /// Loads [uri] in this page and returns where it ended up.
  Future<Uri> go(Uri uri) async {
    _load = Completer<Uri>();
    await web?.loadUrl(urlRequest: URLRequest(url: WebUri('$uri')));
    final url = await _load!.future.timeout(const Duration(seconds: 20));
    session.coordinator.requireCurrent(epoch);
    return url;
  }

  Future<bool?> isListed(CampusEvent event) async {
    final url = await go(eventVerificationUri);
    if (url.path.toLowerCase() != '/mvcteam/act/applyme') return null;
    final raw = await eval(eventListedScript(event.id, event.name));
    if (raw is! String) return null;
    final state = jsonDecode(raw);
    if (state is! Map) return null;
    // A cancelled entry may stay in the list, marked as cancelled.
    return state['listed'] == true && state['cancelled'] != true;
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
    // Reply before navigating; the page unload would discard the result.
    setTimeout(() => button.click(), 0);
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
  // Reply before navigating; the page unload would discard the result.
  setTimeout(() => button.click(), 0);
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
      .sort((a, b) => /取消報名/.test(b.value || b.textContent || '') - /取消報名/.test(a.value || a.textContent || ''))
      .find(b => /取消/.test(b.value || b.textContent || ''));
    if (!button || button.disabled) continue;
    // Reply before navigating; the page unload would discard the result.
    setTimeout(() => button.click(), 0);
    return 'submitted';
  }
  return 'missing';
})()
''';

/// Finds one event in 「我的報名」 by its ID link or exact title and reports
/// whether its row is marked as cancelled. JSON, or null when unreadable.
String eventListedScript(String id, String name) =>
    '''
(() => {
  if (!document.querySelector('.container.body-content')) return null;
  const id = ${jsonEncode(id)};
  const name = ${jsonEncode(name.trim())};
  const byLink = id ? Array.from(document.querySelectorAll('a[href]')).find(a =>
      new RegExp('/Act/(RegData|Apply)/' + id + '(?:[/?#]|\\\$)', 'i').test(a.getAttribute('href'))) : null;
  const byTitle = !byLink && name ? Array.from(document.querySelectorAll('h3')).find(h => h.textContent.trim() === name) : null;
  const hit = byLink || byTitle;
  if (!hit) return JSON.stringify({listed:false});
  const row = hit.closest ? (hit.closest('.enr-list-sec') || hit.closest('.row')) : null;
  const text = row ? (row.innerText || row.textContent || '') : '';
  return JSON.stringify({listed:true, cancelled:/已取消|取消報名成功|報名已取消|已退出/.test(text)});
})()
''';
