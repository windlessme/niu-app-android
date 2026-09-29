/// Policies are service-specific. Never authorize hosts via suffix matching.
class PortalPolicy {
  const PortalPolicy(this.hosts);
  final Set<String> hosts;

  bool allows(Uri uri) =>
      uri.scheme == 'https' &&
      uri.userInfo.isEmpty &&
      uri.port == 443 &&
      hosts.contains(uri.host);

  static const academic = PortalPolicy({
    'ccsys1.niu.edu.tw',
    'ccsys.niu.edu.tw',
    'acade.niu.edu.tw',
  });
  static const moodle = PortalPolicy({'euni.niu.edu.tw'});

  static bool isAttendanceCode(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null || !moodle.allows(uri)) return false;
    final sessions = uri.queryParametersAll['sessid'];
    final secrets = uri.queryParametersAll['qrpass'];
    final sessionId = int.tryParse(uri.queryParameters['sessid'] ?? '');
    return uri.path == '/mod/attendance/attendance.php' &&
        uri.fragment.isEmpty &&
        sessions?.length == 1 &&
        secrets?.length == 1 &&
        (uri.queryParameters['qrpass']?.isNotEmpty ?? false) &&
        sessionId != null &&
        sessionId > 0;
  }
}
