import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../demo/demo_account.dart';
import '../platform/app_version.dart';
import '../session/campus_session.dart';
import '../time/campus_date.dart';
import 'app_analytics.dart';

/// Daily active-device count shared with iOS (`UsageHeartbeatClient`): once
/// per Taipei day, a random installation id, the platform and the version.
///
/// Never accounts or school data. The id is kept apart from any account, so
/// signing out does not reset it, and backups never carry it to another
/// phone (the app excludes all its data from backup and device transfer).
/// Best effort: a failure stays silent and is retried on the next return to
/// the app.
class UsageHeartbeat {
  UsageHeartbeat({
    Future<int?> Function(String body)? post,
    Future<String?> Function()? version,
    DateTime Function()? clock,
    Random? random,
  }) : _post = post ?? _send,
       _version = version ?? (() async => (await AppVersion.current())?.name),
       _clock = clock ?? DateTime.now,
       _random = random ?? Random.secure();

  static final instance = UsageHeartbeat();
  static const endpoint = 'https://niu-api.chien.dev/v1/usage/heartbeat';
  static const idKey = 'usageHeartbeat.installationId';
  static const dayKey = 'usageHeartbeat.lastReportedDay';

  final Future<int?> Function(String body) _post;
  final Future<String?> Function() _version;
  final DateTime Function() _clock;
  final Random _random;
  bool _reporting = false;

  /// Off where real devices must not be counted: debug and store-screenshot
  /// builds, and anyone who turned statistics off with the former switch.
  static bool get allowed =>
      !kDebugMode && !storeScreenshots && AppAnalytics.instance.enabled;

  static final _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );
  static final _versionPattern = RegExp(r'^[0-9]{1,4}(\.[0-9]{1,4}){0,2}$');

  /// One to three numeric parts, or not sent at all.
  static String? reportableVersion(String? value) =>
      value != null && _versionPattern.hasMatch(value) ? value : null;

  /// May be called often; sends at most once per Taipei day, after a 204.
  Future<void> report() async {
    if (_reporting) return;
    _reporting = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final day = CampusDate.at(_clock());
      final today =
          '${day.year.toString().padLeft(4, '0')}-'
          '${day.month.toString().padLeft(2, '0')}-'
          '${day.day.toString().padLeft(2, '0')}';
      if (prefs.getString(dayKey) == today) return;
      final version = reportableVersion(await _version());
      final body = jsonEncode({
        'installation_id': await _installationId(prefs),
        'platform': 'android',
        'app_version': ?version,
      });
      if (await _post(body) == 204) await prefs.setString(dayKey, today);
    } catch (_) {
      // Statistics never get in the way of the app.
    } finally {
      _reporting = false;
    }
  }

  Future<String> _installationId(SharedPreferences prefs) async {
    final saved = prefs.getString(idKey)?.toLowerCase();
    if (saved != null && _uuid.hasMatch(saved)) return saved;
    final created = uuidV4(_random);
    await prefs.setString(idKey, created);
    return created;
  }

  /// A random RFC 4122 version 4 UUID, lowercase.
  static String uuidV4(Random random) {
    final bytes = [for (var i = 0; i < 16; i++) random.nextInt(256)];
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')];
    return '${hex.sublist(0, 4).join()}-${hex.sublist(4, 6).join()}-'
        '${hex.sublist(6, 8).join()}-${hex.sublist(8, 10).join()}-'
        '${hex.sublist(10).join()}';
  }

  /// No cookies, cache or redirects; four-second timeouts.
  static Future<int?> _send(String body) async {
    final http = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 4),
        sendTimeout: const Duration(seconds: 4),
        receiveTimeout: const Duration(seconds: 4),
        followRedirects: false,
        validateStatus: (_) => true,
        responseType: ResponseType.plain,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );
    try {
      return (await http.post<String>(endpoint, data: body)).statusCode;
    } finally {
      http.close(force: true);
    }
  }
}

/// When to call [UsageHeartbeat.report], as on iOS: after signing in or
/// restoring a sign-in, on every return to the app, and at Taipei midnight
/// while the app stays open. Only for a signed-in school account: not the
/// review demo, and never from widgets or background work.
class UsageHeartbeatTrigger {
  UsageHeartbeatTrigger(
    this.session, {
    UsageHeartbeat? heartbeat,
    bool Function()? allowed,
    DateTime Function()? clock,
  }) : heartbeat = heartbeat ?? UsageHeartbeat.instance,
       _allowed = allowed ?? (() => UsageHeartbeat.allowed),
       _clock = clock ?? DateTime.now;

  final CampusSession session;
  final UsageHeartbeat heartbeat;
  final bool Function() _allowed;
  final DateTime Function() _clock;
  AppLifecycleListener? _lifecycle;
  Timer? _midnight;
  bool _signedIn = false;

  void start() {
    session.addListener(_sessionChanged);
    _lifecycle = AppLifecycleListener(
      onResume: () {
        _armMidnight();
        report();
      },
      onPause: () => _midnight?.cancel(),
    );
    _armMidnight();
    _sessionChanged();
  }

  void dispose() {
    session.removeListener(_sessionChanged);
    _lifecycle?.dispose();
    _midnight?.cancel();
  }

  /// A new sign-in or a restored one; other session updates are not.
  void _sessionChanged() {
    final now = session.isSignedIn && !session.isDemo;
    if (now && !_signedIn) report();
    _signedIn = now;
  }

  void report() {
    if (!session.isSignedIn || session.isDemo || !_allowed()) return;
    unawaited(heartbeat.report());
  }

  /// Just after the next Taipei midnight, while in the foreground.
  void _armMidnight() {
    _midnight?.cancel();
    final now = _clock().toUtc();
    final taipei = now.add(const Duration(hours: 8));
    final next = DateTime.utc(
      taipei.year,
      taipei.month,
      taipei.day + 1,
    ).subtract(const Duration(hours: 8));
    _midnight = Timer(next.difference(now) + const Duration(seconds: 5), () {
      _armMidnight();
      report();
    });
  }
}
