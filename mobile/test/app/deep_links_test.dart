import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/app/deep_links.dart';

void main() {
  test('native links map known hosts and drop secret query parameters', () {
    expect(campusDeepLink(Uri.parse('niulife://schedule')), '/schedule');
    expect(campusDeepLink(Uri.parse('niulife://moodle')), '/moodle');
    expect(campusDeepLink(Uri.parse('niulife://calendar')), '/calendar');
    expect(
      campusDeepLink(Uri.parse('niulife://attendance?qrpass=ignored')),
      '/attendance',
    );
    expect(campusDeepLink(Uri.parse('niulife://library')), '/library');
    expect(campusDeepLink(Uri.parse('https://schedule')), isNull);
    expect(campusDeepLink(Uri.parse('niulife://unknown')), isNull);
    expect(campusDeepLink(Uri.parse('niulife://library/arbitrary')), isNull);
  });

  test('niu-life.app App Links open the app or one of its places', () {
    expect(campusDeepLink(Uri.parse('https://niu-life.app/download')), '/');
    expect(
      campusDeepLink(
        Uri.parse('https://niu-life.app/download?utm_source=poster'),
      ),
      '/',
    );
    expect(
      campusDeepLink(Uri.parse('https://niu-life.app/open/schedule')),
      '/schedule',
    );
    expect(
      campusDeepLink(Uri.parse('https://niu-life.app/open/attendance')),
      '/attendance',
    );
    // Flutter may hand over only the path.
    expect(campusDeepLink(Uri.parse('/open/mail')), '/mail');
    expect(campusDeepLink(Uri.parse('/download')), '/');
    // Unknown places, other hosts and plain http are not ours.
    expect(
      campusDeepLink(Uri.parse('https://niu-life.app/open/settings')),
      isNull,
    );
    expect(
      campusDeepLink(Uri.parse('https://niu-life.app/open/schedule/extra')),
      isNull,
    );
    expect(
      campusDeepLink(Uri.parse('https://evil.test/open/schedule')),
      isNull,
    );
    expect(
      campusDeepLink(Uri.parse('http://niu-life.app/open/schedule')),
      isNull,
    );
    expect(campusDeepLink(Uri.parse('https://niu-life.app/privacy')), isNull);
    // Ordinary in-app routes are left alone.
    expect(campusDeepLink(Uri.parse('/schedule')), isNull);
  });
}
