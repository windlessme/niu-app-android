import 'package:flutter/services.dart';

/// Installed version as reported by Android (versionName and versionCode).
class AppVersion {
  const AppVersion(this.name, this.build);
  final String name, build;

  @override
  String toString() => build.isEmpty ? name : '$name ($build)';

  static const channel = MethodChannel('niulife/app');
  static Future<AppVersion?>? _cached;

  /// Null where the platform cannot report it (tests, unsupported hosts).
  static Future<AppVersion?> current() => _cached ??= () async {
    try {
      final data = await channel.invokeMapMethod<String, String>('version');
      final name = data?['name'] ?? '';
      return name.isEmpty ? null : AppVersion(name, data?['build'] ?? '');
    } catch (_) {
      return null;
    }
  }();
}
