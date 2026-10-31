import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/core/network/school_trust.dart';

void main() {
  test('the bundled TWCA CYBER root parses as a trusted certificate', () {
    expect(
      () => SecurityContext(
        withTrustedRoots: false,
      ).setTrustedCertificatesBytes(utf8.encode(SchoolTrust.twcaCyberRoot)),
      returnsNormally,
    );
  });

  test('the school context adds to the device roots without failing', () {
    expect(SchoolTrust.schoolContext, returnsNormally);
  });

  test('installed overrides build clients with the school context', () {
    final previous = HttpOverrides.current;
    addTearDown(() => HttpOverrides.global = previous);
    SchoolTrust.install();
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    expect(HttpOverrides.current, isA<SchoolTrust>());
  });
}
