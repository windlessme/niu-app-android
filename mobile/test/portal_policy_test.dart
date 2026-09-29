import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/core/web/portal_policy.dart';

void main() {
  test('attendance only accepts the exact HTTPS school endpoint', () {
    const valid =
        'https://euni.niu.edu.tw/mod/attendance/attendance.php?qrpass=fixture&sessid=1';
    expect(PortalPolicy.isAttendanceCode(valid), isTrue);
    for (final invalid in [
      valid.replaceFirst('https:', 'http:'),
      valid.replaceFirst('euni.niu.edu.tw', 'euni.niu.edu.tw.attacker.example'),
      valid.replaceFirst('euni.niu.edu.tw', 'user@euni.niu.edu.tw'),
      valid.replaceFirst('euni.niu.edu.tw', 'euni.niu.edu.tw:8443'),
      valid.replaceFirst('sessid=1', 'sessid=bad'),
      '$valid&sessid=2',
      '$valid#fragment',
      valid.replaceFirst('sessid=1', 'sessid=-1'),
      valid.replaceFirst('attendance.php', 'view.php'),
    ]) {
      expect(PortalPolicy.isAttendanceCode(invalid), isFalse);
    }
  });
}
