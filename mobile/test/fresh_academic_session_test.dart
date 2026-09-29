import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/core/network/school_clients.dart';
import 'package:niu_mobile/core/session/campus_session.dart';
import 'features/authentication_session_test.dart' show MemoryVault;

class FreshSso extends SsoApiClient {
  FreshSso() : super(schoolClient('https://ccsys1.niu.edu.tw'));
  int verifications = 0;
  @override
  Future<Map<String, dynamic>> verifyIdentity(
    String token,
    String account,
  ) async {
    verifications++;
    return {'acnt': account, 'chName': '測試'};
  }

  @override
  Future<Uri> academicEntry(String token, String account) async =>
      Uri.parse('https://acade.niu.edu.tw/NIU/Login.aspx?GUID=fixture');
}

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
