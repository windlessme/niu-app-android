import 'dart:io';
import 'package:niu_mobile/features/authentication/school_login_capture.dart';

void main() {
  stdout.writeln(
    schoolLoginPrefillScript(
      const SubmittedSchoolCredentials(
        'b123',
        '";window.injected=true;//</script>\n密碼\\',
      ),
    ),
  );
}
