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
    if (target && url.origin === new URL(target).origin && url.pathname.toLowerCase() === new URL(target).pathname.toLowerCase()) return doc.readyState === 'complete' ? 'ready' : null;
  }
  for (const doc of docs) {
    const url = new URL(doc.location.href);
    if (/\\/std002\\.aspx\$/i.test(url.pathname)) {
      const link = doc.getElementById('ctl00_ContentPlaceHolder1_RadListView1_ctrl0_HyperLink1');
      if (link && link.getAttribute('href')) return new URL(link.getAttribute('href'), url).href;
    }
    if (url.hostname === 'acade.niu.edu.tw' && /\\/mainframe\\.aspx\$/i.test(url.pathname) && doc.readyState === 'complete') return target || 'ready';
    // Login.aspx owns the GUID exchange and redirect. Never interrupt it.
  }
  return null;
})()
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

/// Evaluate a complete script, including trailing semicolons, as an expression.
String academicFrameSnapshotScript(String script) =>
    '''
(() => {
  let count = 0;
  const timer = setInterval(() => {
    if (++count > 80) { clearInterval(timer); return; }
    if (!['acade.niu.edu.tw','ccsys.niu.edu.tw'].includes(location.hostname)) return;
    try {
      const result = (0, eval)(${jsonEncode(script)});
      if (result && window.flutter_inappwebview) {
        window.flutter_inappwebview.callHandler('academicSnapshot', result);
        clearInterval(timer);
      }
    } catch (_) {}
  }, 750);
})();
''';

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
