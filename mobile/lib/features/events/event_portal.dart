import 'dart:convert';
import '../../core/session/campus_session.dart';
import 'event_login_service.dart';

/// Use the shared event cookies; SSO's GUID does not authenticate MvcTeam.
Future<Uri> eventPortalEntry(CampusSession session) async {
  final epoch = session.coordinator.epoch;
  if (!session.hasLocalAccount) throw StateError('請先登入校務帳號');
  await EventLoginService().restore(session, epoch);
  session.coordinator.requireCurrent(epoch);
  return eventListUri;
}

String eventNavigationScript(Uri target) =>
    '''
(() => {
  if (document.readyState !== 'complete') return null;
  const url = new URL(location.href);
  if (url.origin !== 'https://ccsys.niu.edu.tw') return null;
  if (url.pathname.toLowerCase() === '/mvcteam/account/login' ||
      document.querySelector('input[type="password"], #loginLink')) return 'login-required';
  const target = new URL(${jsonEncode(target.toString())});
  const path = url.pathname.replace(/\\/\$/, '').toLowerCase();
  if (path === target.pathname.replace(/\\/\$/, '').toLowerCase() &&
      (document.body?.innerText || '').trim()) return 'ready';
  if (path === '/mvcteam/act' || path === '/mvcteam') return target.href;
  return null;
})()
''';
