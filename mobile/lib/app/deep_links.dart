/// Destinations a link may open, by name; nothing else is reachable.
const _destinations = {
  'schedule': '/schedule',
  'attendance': '/attendance',
  'library': '/library',
  'mail': '/mail',
  'moodle': '/moodle',
  'calendar': '/calendar',
};

/// The site whose links the app handles (verified by its assetlinks.json).
const appLinkHost = 'niu-life.app';

/// Accept only known app destinations; do not forward arbitrary URI parameters.
///
/// - `niulife://schedule` and the other shortcuts.
/// - App Links: `https://niu-life.app/open/schedule` opens the same place,
///   and `https://niu-life.app/download` just opens the app. Flutter may
///   pass these whole or as a bare path, so both are accepted.
String? campusDeepLink(Uri uri) {
  if (uri.userInfo.isNotEmpty || uri.hasPort) return null;
  if (uri.scheme == 'niulife') {
    if (uri.path.isNotEmpty && uri.path != '/') return null;
    return _destinations[uri.host];
  }
  final web = uri.scheme == 'https' && uri.host == appLinkHost;
  final bare = !uri.hasScheme && uri.host.isEmpty;
  if (!web && !bare) return null;
  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (segments.length == 1 && segments.first == 'download') return '/';
  if (segments.length == 2 && segments.first == 'open') {
    return _destinations[segments.last];
  }
  return null;
}
