import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract class CredentialVault {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> clear();
}

class DeviceCredentialVault implements CredentialVault {
  DeviceCredentialVault(this.storage);
  final FlutterSecureStorage storage;
  static const _prefix = 'niu.session.';
  static const _keys = [
    'ssoToken',
    'ssoAccount',
    'ssoProfile',
    'moodleToken',
    'moodlePrivateToken',
    'moodleSession',
    'eventSession',
    'scheduleCache',
    'graduationCache',
    'leaveCache',
    'rememberedSchoolLogin',
    'pendingCleanup',
  ];

  void _validate(String key) {
    if (!_keys.contains(key)) throw ArgumentError.value(key, 'key');
  }

  @override
  Future<String?> read(String key) {
    _validate(key);
    return storage.read(key: '$_prefix$key');
  }

  @override
  Future<void> write(String key, String value) {
    _validate(key);
    return storage.write(key: '$_prefix$key', value: value);
  }

  @override
  Future<void> clear() async {
    Object? failure;
    for (final key in _keys) {
      if (key == 'pendingCleanup') continue;
      try {
        await storage.delete(key: '$_prefix$key');
      } catch (error) {
        failure ??= error;
      }
    }
    if (failure != null) throw failure;
  }
}
