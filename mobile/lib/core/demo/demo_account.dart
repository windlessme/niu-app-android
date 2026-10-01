import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Google Play review account. It never reaches the school: signing in with
/// it switches the app to built-in sample data and simulated submissions.
const demoAccount = 'niulifedemo';

/// SHA-256 of the review password; the password itself is not shipped.
const _demoPasswordSha256 =
    '732d71d66e08d1b04412c9d8426694d93d65f52d15665d30e0d0b56cac8b9665';

/// Build flag for Play Store screenshots: the demo looks as it does for a
/// signed-in student, without demo-mode notices. Never set for releases.
const storeScreenshots = bool.fromEnvironment('NIU_STORE_SCREENSHOTS');

bool isDemoLogin(String account, String password) =>
    account.trim().toLowerCase() == demoAccount &&
    sha256.convert(utf8.encode(password)).toString() == _demoPasswordSha256;
