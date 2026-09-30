import 'dart:io';
import 'package:niu_mobile/features/authentication/school_login_scripts.dart';

/// Emits the fill script with a hostile password for sso_login_fill_dom.cjs.
void main() {
  stdout.writeln(
    schoolLoginFillScript('b123', '";window.injected=true;//</script>密碼\\'),
  );
}
