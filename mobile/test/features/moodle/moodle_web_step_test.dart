import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/features/moodle/moodle_web_session.dart';

void main() {
  final target = Uri.https('euni.niu.edu.tw', '/mod/attendance/view.php', {
    'id': '5',
  });
  final login = Uri.https('euni.niu.edu.tw', '/login/index.php');
  MoodleWebStep step(
    Uri page, {
    bool loginForm = false,
    bool signedOut = false,
    bool triedKey = false,
    bool triedPassword = false,
    bool exact = true,
  }) => moodleWebStep(
    page: page,
    target: target,
    loginForm: loginForm,
    signedOut: signedOut,
    triedKey: triedKey,
    triedPassword: triedPassword,
    exact: exact,
  );

  test('signed-in target page is done without any login', () {
    expect(step(target), MoodleWebStep.done);
  });

  test('login form tries the key, then the password, then gives up', () {
    expect(step(login, loginForm: true), MoodleWebStep.useKey);
    expect(
      step(login, loginForm: true, triedKey: true),
      MoodleWebStep.submitPassword,
    );
    expect(
      step(login, loginForm: true, triedKey: true, triedPassword: true),
      MoodleWebStep.fail,
    );
  });

  test('a signed-out page outside /login/ also needs signing in', () {
    expect(step(target, signedOut: true), MoodleWebStep.useKey);
  });

  test('stopping on autologin.php means the key failed', () {
    final autologin = Uri.https(
      'euni.niu.edu.tw',
      '/admin/tool/mobile/autologin.php',
    );
    expect(step(autologin, triedKey: true), MoodleWebStep.retarget);
    expect(
      step(autologin, triedKey: true, triedPassword: true),
      MoodleWebStep.fail,
    );
  });

  test('redirects in between are waited out', () {
    expect(
      step(
        Uri.https('euni.niu.edu.tw', '/login/index.php', {'testsession': '7'}),
      ),
      MoodleWebStep.wait,
    );
    expect(step(Uri.https('sso.niu.edu.tw', '/')), MoodleWebStep.wait);
  });

  test('another signed-in page is retargeted only for exact reads', () {
    final dashboard = Uri.https('euni.niu.edu.tw', '/my/');
    expect(step(dashboard), MoodleWebStep.retarget);
    expect(step(dashboard, exact: false), MoodleWebStep.done);
  });
}
