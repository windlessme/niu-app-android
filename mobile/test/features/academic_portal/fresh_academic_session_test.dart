import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/core/session/campus_session.dart';
import '../../support/fakes.dart';

void main() {
  test(
    'fresh verified login opens academic entry without a second restore',
    () async {
      final api = FreshSso();
      final session = CampusSession(vault: MemoryVault(), sso: api);
      await session.acceptToken('fresh-token', 'b123');
      expect((await session.academicEntry()).host, 'acade.niu.edu.tw');
      expect(api.verifications, 1);
      session.dispose();
    },
  );
}
