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
}
