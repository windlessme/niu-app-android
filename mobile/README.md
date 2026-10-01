# NIU-Life Flutter Android

Flutter SDK: **3.47.5**, Java **17**, Android SDK **36**.
Android build: AGP **8.11.1**, Gradle **8.14.3**, Kotlin **2.2.20**.
AGP 9 is not yet compatible with the selected InAppWebView Android package;
see the build decision in `../docs/android-flutter-architecture.md`.
Flutter currently accepts this combination but prints future-support warnings.

## Run

```sh
flutter pub get --enforce-lockfile
python3 tool/sync_calendar.py
flutter run
```

## Verify and build

```sh
bash tool/verify.sh
flutter build apk --debug
```

School-page DOM regression fixtures run as part of `tool/verify.sh` using Node.js.
For an attached Android device, the real Chromium WebView extraction fixture is:

```sh
flutter test integration_test/academic_dom_test.dart -d <device-id>
```

It loads synthetic HTML, not a real school account, and verifies native WebView
dimensions and the production schedule/graduation extraction scripts.

For an already booted Android emulator/device:

```sh
bash tool/smoke_android.sh
```

This installs the debug APK and checks home/calendar navigation using UI
Automator. Screenshots and UI dumps are written to `/tmp/opencode` on this
development host.

The preview integrates SSO, academic schedule/grades/graduation/events,
Moodle courses/announcements/resources/assignments/grades, attendance scanning,
library codes, cached calendars, settings, desktop widgets and local reminders.
School workflows have fixture coverage but still require live account/device
validation. Advanced school forms remain available through authenticated WebViews.
Since 0.2.4, saved schedules open immediately and only manual refresh queries the
school. The school-page credential submission can establish Moodle tokens in the
same login; existing token-only installations may need one school login to seed
that envelope. Since 0.2.5 the same credential submission also establishes the
event system's separate form-based session. Saved event cookies are reused;
expired sessions provide a school-login reconnect action preserving the target.
Use real accounts only in manual device testing; never commit credentials.

The application ID is `me.windless.niulife`, the permanent Google Play package name.
Confirm the publisher-owned permanent ID before the first Play upload.

Calendar assets are generated from `../calendar-data`, including index hashes.
Update the canonical data first, then run the sync tool. CI checks for drift.

The repository interfaces can be overridden through Riverpod for fixtures;
see `test/app_navigation_test.dart`. Unit tests never contact school services.

Since 0.4.1, a rejected SSO restore marks only school authentication as needing
reconnection. Local timetable data and independent Moodle/event credentials are
retained. Explicit logout still clears all account-scoped data. Credentials
already removed by an older version cannot be recovered by the upgrade.

Since 0.5.1, successful school login automatically remembers verified credentials
in the device credential vault, without a checkbox. Since 0.10.0 login matches
iOS: a native form supplies 學號／密碼, the app fills and submits the school SSO
page out of sight once its human verification enables 登入, and shows the page
only when interaction is needed. Credentials the school rejects are forgotten.
Users can forget credentials in Settings, and explicit logout also removes them.

The registration feature uses the school's ENR5020 registration query and the
currently authenticated student's enrollment certificate. Certificate bytes must
pass PDF validation before preview/export; private documents never enter the
public APK download directory.

See [architecture and maintenance notes](../docs/android-flutter-architecture.md).
