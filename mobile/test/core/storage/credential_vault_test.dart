import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/core/session/campus_session.dart';
import 'package:niu_mobile/core/storage/credential_vault.dart';
import 'package:niu_mobile/features/events/event_favorites.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final data = <String, String>{};

  setUp(() {
    data.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          final args = call.arguments as Map;
          final key = args['key'] as String;
          switch (call.method) {
            case 'write':
              data[key] = args['value'] as String;
              return null;
            case 'read':
              return data[key];
            case 'delete':
              data.remove(key);
              return null;
          }
          throw UnsupportedError(call.method);
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'vault uses dedicated keys and clears all supported credentials',
    () async {
      final vault = DeviceCredentialVault(const FlutterSecureStorage());
      await vault.write('ssoToken', 'fixture-sso');
      await vault.write('moodleToken', 'fixture-moodle');
      await vault.write('moodleSession', 'fixture-envelope');
      await vault.write('eventSession', 'fixture-event-cookie');
      await vault.write('graduationCache', 'fixture-graduation');
      await vault.write('portalCache', 'fixture-grades');
      await vault.write(
        'rememberedSchoolLogin',
        'fixture-encrypted-storage-value',
      );
      expect(await vault.read('ssoToken'), 'fixture-sso');
      data['unrelated.setting'] = 'keep';
      await vault.clear();
      expect(data, {'unrelated.setting': 'keep'});
      expect(() => vault.read('password'), throwsArgumentError);
    },
  );

  test('review demo persists through the device vault and logs out', () async {
    // MemoryVault accepts any key; the device vault has an allowlist.
    final vault = DeviceCredentialVault(const FlutterSecureStorage());
    final session = CampusSession(vault: vault, platformCleanup: []);
    await session.enterDemo();
    final restored = CampusSession(vault: vault, platformCleanup: []);
    await restored.restore();
    expect(restored.isDemo, isTrue);
    await restored.logout();
    expect(data.keys.where((k) => k.startsWith('niu.session.')), [
      'niu.session.pendingCleanup',
    ]);
    session.dispose();
    restored.dispose();
  });

  test(
    'event favorites are stored on the device and cleared on logout',
    () async {
      final vault = DeviceCredentialVault(const FlutterSecureStorage());
      final session = CampusSession(vault: vault, platformCleanup: []);
      addTearDown(session.dispose);
      session.account = 'b123';
      final favorites = EventFavorites(session);
      expect(await favorites.set(['11201'], favorite: true), {'11201'});
      expect(await favorites.load(), {'11201'});
      await vault.clear();
      expect(await favorites.load(), isEmpty);
    },
  );
}
