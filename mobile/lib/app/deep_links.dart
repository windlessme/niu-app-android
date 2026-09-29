/// Accept only known app destinations; do not forward arbitrary URI parameters.
String? campusDeepLink(Uri uri) {
  if (uri.scheme != 'niulife' || uri.userInfo.isNotEmpty || uri.hasPort) {
    return null;
  }
  if (uri.path.isNotEmpty && uri.path != '/') return null;
  return switch (uri.host) {
    'schedule' => '/schedule',
    'attendance' => '/attendance',
    'library' => '/library',
    _ => null,
  };
}
