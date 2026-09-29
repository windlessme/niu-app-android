import 'dart:convert';

/// Read-only discovery: frames can finish loading without a top-level callback.
String academicNavigationScript(Uri? target) =>
    '''
(() => {
  const docs = [];
  function collect(w) { try { docs.push(w.document); for (let i=0;i<w.frames.length;i++) collect(w.frames[i]); } catch (_) {} }
  collect(window);
  const target = ${jsonEncode(target?.toString())};
  for (const doc of docs) {
    const url = new URL(doc.location.href);
    if (url.hostname === 'acade.niu.edu.tw' &&
        (/\\/(?:timeoutpage|default)\\.aspx\$/i.test(url.pathname) ||
         (/\\/login\\.aspx\$/i.test(url.pathname) && !Array.from(url.searchParams).some(([key, value]) => key.toLowerCase() === 'guid' && value)))) return 'session-expired';
    if (url.hostname === 'ccsys1.niu.edu.tw' && /^\\/sso(?:\\/|\$)/i.test(url.pathname)) return 'session-expired';
  }
  const interaction = (0, eval)(${jsonEncode(portalInteractionScript)});
  if (interaction) return interaction;
  for (const doc of docs) {
    const url = new URL(doc.location.href);
    if (target && url.origin === new URL(target).origin && url.pathname.toLowerCase() === new URL(target).pathname.toLowerCase()) return doc.readyState === 'complete' ? 'ready' : null;
  }
  for (const doc of docs) {
    const url = new URL(doc.location.href);
    if (/\\/std002\\.aspx\$/i.test(url.pathname)) {
      const link = doc.getElementById('ctl00_ContentPlaceHolder1_RadListView1_ctrl0_HyperLink1');
      if (link && link.getAttribute('href')) return new URL(link.getAttribute('href'), url).href;
    }
    if (url.hostname === 'acade.niu.edu.tw' && /\\/mainframe\\.aspx\$/i.test(url.pathname) && doc.readyState !== 'loading') return target || 'ready';
    // Login.aspx owns the GUID exchange and redirect. Never interrupt it.
  }
  return null;
})()
''';

/// Only reveal visible login/challenge controls, not hidden CAPTCHA tokens.
const portalInteractionScript = r'''
(() => {
  function inspect(w) {
    try {
      const d = w.document;
      if (['acade.niu.edu.tw', 'ccsys.niu.edu.tw', 'ccsys1.niu.edu.tw', 'sso.niu.edu.tw'].includes(new URL(d.location.href).hostname)) {
        const controls = d.querySelectorAll('input[type="password"], input[id*="captcha" i], input[name*="captcha" i], input[id*="validatecode" i], input[name*="verifycode" i], .g-recaptcha, .h-captcha, .cf-turnstile, iframe[src*="recaptcha"], iframe[src*="hcaptcha"], iframe[src*="challenges.cloudflare.com"]');
        for (const control of controls) {
          if (control.type !== 'hidden' && control.getClientRects().length && w.getComputedStyle(control).visibility !== 'hidden') return 'interaction-required';
        }
      }
      for (let i = 0; i < w.frames.length; i++) {
        const result = inspect(w.frames[i]);
        if (result) return result;
      }
    } catch (_) {}
    return null;
  }
  return inspect(window);
})()
''';

/// Wake the host as soon as the frame DOM is usable, without waiting for images
/// or unrelated frames. Periodic host polling remains the bounded fallback.
const academicNavigationWakeupScript = r'''
(() => {
  if (!['acade.niu.edu.tw', 'ccsys.niu.edu.tw', 'ccsys1.niu.edu.tw'].includes(location.hostname)) return;
  function wake() {
    if (document.readyState !== 'loading' && window.flutter_inappwebview) {
      window.flutter_inappwebview.callHandler('academicSnapshot');
    }
  }
  document.addEventListener('readystatechange', wake);
  window.addEventListener('flutterInAppWebViewPlatformReady', wake);
  wake();
})();
''';

/// Read preparation and extraction in one JS turn. A document signature lets the
/// host discard results whose frame navigated while evaluateJavascript returned.
String academicReadScript({
  required String extract,
  required String run,
  String? prepare,
}) =>
    '''
(() => {
  ${academicDocumentScript(run)}
  const signature = identify(window);
  if (!signature) return null;
  if (${prepare == null ? 'false' : '(0, eval)(${jsonEncode(prepare)}) !== true'}) return null;
  const value = (0, eval)(${jsonEncode(extract)});
  return value ? JSON.stringify({signature, value}) : null;
})()
''';

String academicDocumentScript(String run) =>
    '''
function identify(w) {
  try {
    const d = w.document;
    if (!d.__niuDocumentId) {
      d.__niuDocumentId = Math.random().toString(36).slice(2);
      if (w.addEventListener) w.addEventListener('beforeunload', () => { d.__niuLeaving = true; });
    }
    w.__niuAcademicRun = ${jsonEncode(run)};
    let ids = [d.__niuDocumentId + ':' + d.readyState + ':' + !!d.__niuLeaving + ':' + d.location.href];
    for (let i = 0; i < w.frames.length; i++) ids.push(identify(w.frames[i]));
    return ids.join('|');
  } catch (_) { return ''; }
}
''';

String academicDocumentIdentityScript(String run) =>
    '(() => { ${academicDocumentScript(run)} return identify(window); })()';

String academicMenuScript(String label) =>
    '''
(() => {
  const docs = [];
  function collect(w) { try { docs.push(w.document); for(let i=0;i<w.frames.length;i++) collect(w.frames[i]); } catch (_) {} }
  collect(window);
  for (const label of [${jsonEncode(label)}, '成績查詢作業', '成績及計分冊']) {
    for (const doc of docs) {
      const link = Array.from(doc.querySelectorAll('a')).find(a => a.textContent.replace(/\\s+/g, '').includes(label));
      if (link && !link.dataset.niuMenuOpened) {
        link.dataset.niuMenuOpened = 'true';
        link.click(); return label === ${jsonEncode(label)};
      }
    }
  }
  return false;
})()
''';
