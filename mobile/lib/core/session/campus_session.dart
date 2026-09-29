import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../network/school_clients.dart';
import '../platform/schedule_gateway.dart';
import '../storage/credential_vault.dart';
import 'session_coordinator.dart';
import 'cached_schedule.dart';
import 'cached_graduation.dart';

/// One owner for all school WebViews, credentials, and logout generations.
class CampusSession extends ChangeNotifier {
  CampusSession({
    CredentialVault? vault,
    SsoApiClient? sso,
    this.platformCleanup,
  }) : vault = vault ?? DeviceCredentialVault(const FlutterSecureStorage()),
       sso = sso ?? SsoApiClient(schoolClient('https://ccsys1.niu.edu.tw'));

  static final instance = CampusSession();
  final CredentialVault vault;
  final SsoApiClient sso;
  final coordinator = SessionCoordinator();
  final List<Future<void> Function()>? platformCleanup;
  bool isOffline = false;
  bool ssoNeedsReauthentication = false;
  bool get hasLocalAccount => account != null && !cleanupPending;
  int _identityGeneration = 0;
  Future<void>? _revalidation;
  bool cleanupPending = false;
  CachedSchedule? cachedSchedule;
  CachedGraduation? cachedGraduation;
  Future<void>? _cacheWrite;
  Future<void>? _graduationWrite;
  int _graduationRevision = 0;
  final Set<Future<void> Function()> _cleanup = {};
  String? account;
  String? _token;
  int? _academicEpoch;
  String? _academicAccount;

  /// A successful protected-page read permits reusing the shared WebView cookies.
  /// This is only a routing hint: an expired page still requires a fresh bridge.
  bool get hasAcademicSession =>
      isSignedIn &&
      !cleanupPending &&
      _academicEpoch == coordinator.epoch &&
      _academicAccount == account;

  void confirmAcademicSession(int epoch) {
    coordinator.requireCurrent(epoch);
    if (!isSignedIn) return;
    _academicEpoch = epoch;
    _academicAccount = account;
  }

  void invalidateAcademicSession(int epoch) {
    coordinator.requireCurrent(epoch);
    _academicEpoch = null;
    _academicAccount = null;
  }

  Map<String, dynamic> profile = {};
  Future<void>? _restore;
  Future<void>? _persist;
  Future<void>? _nativeWrite;
  bool get isSignedIn => account != null && _token != null;
  String get displayName => profile['chName']?.toString() ?? account ?? '訪客';
  void registerCleanup(Future<void> Function() callback) =>
      _cleanup.add(callback);
  void unregisterCleanup(Future<void> Function() callback) =>
      _cleanup.remove(callback);

  Future<void> restore() => _restore ??= _restoreSession();

  /// Explicit retry for an offline session after connectivity returns.
  Future<void> retryRestore() {
    return _revalidation ??= _restoreSession().whenComplete(
      () => _revalidation = null,
    );
  }

  Future<void> _restoreSession() async {
    await recoverCleanup();
    final epoch = coordinator.epoch;
    final identityGeneration = _identityGeneration;
    final graduationRevision = _graduationRevision;
    final savedAccount = await vault.read('ssoAccount');
    final savedToken = await vault.read('ssoToken');
    if (savedAccount == null || savedToken == null) return;
    final cachedProfile = await vault.read('ssoProfile');
    final cached = await vault.read('scheduleCache');
    coordinator.requireCurrent(epoch);
    if (identityGeneration != _identityGeneration) return;
    CachedSchedule? schedule;
    try {
      if (cached != null) {
        schedule = CachedSchedule.fromJson(
          jsonDecode(cached) as Map<String, dynamic>,
        );
      }
    } catch (_) {}
    CachedGraduation? graduation;
    try {
      final raw = await vault.read('graduationCache');
      if (raw != null && raw.isNotEmpty) {
        final restored = CachedGraduation.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
        if (restored.account == savedAccount) graduation = restored;
      }
    } catch (_) {
      // A damaged optional cache must not block restoration of other services.
    }
    coordinator.requireCurrent(epoch);
    if (identityGeneration != _identityGeneration) return;
    try {
      final verified = await sso.verifyIdentity(savedToken, savedAccount);
      coordinator.requireCurrent(epoch);
      if (identityGeneration != _identityGeneration) return;
      account = savedAccount;
      _token = savedToken;
      profile = verified;
      isOffline = false;
      ssoNeedsReauthentication = false;
      cachedSchedule = schedule?.account == savedAccount ? schedule : null;
      if (graduationRevision == _graduationRevision) {
        cachedGraduation = graduation;
      }
      notifyListeners();
    } catch (error) {
      coordinator.requireCurrent(epoch);
      if (identityGeneration != _identityGeneration) return;
      final rejected =
          (error is SchoolApiException &&
              error.code == 'sso_identity_mismatch') ||
          (error is DioException &&
              [401, 403].contains(error.response?.statusCode));
      account = savedAccount;
      _token = null;
      isOffline = !rejected;
      ssoNeedsReauthentication = rejected;
      try {
        profile = cachedProfile == null
            ? {}
            : Map<String, dynamic>.from(jsonDecode(cachedProfile) as Map);
      } catch (_) {
        profile = {};
      }
      cachedSchedule = schedule?.account == savedAccount ? schedule : null;
      if (graduationRevision == _graduationRevision) {
        cachedGraduation = graduation;
      }
      notifyListeners();
    }
  }

  Future<void> acceptToken(
    String token,
    String? expectedAccount, {
    int? epoch,
  }) async {
    await recoverCleanup();
    final captured = epoch ?? coordinator.epoch;
    coordinator.requireCurrent(captured);
    // A redirected school login page may no longer contain its username field.
    // Discover it from authenticated server data, never from JWT claims or DOM.
    expectedAccount ??= (await sso.info(token))['acnt'] as String;
    coordinator.requireCurrent(captured);
    final owner = expectedAccount.trim().toLowerCase();
    final savedOwner = await vault.read('ssoAccount');
    coordinator.requireCurrent(captured);
    if (savedOwner != null && savedOwner != owner) {
      throw StateError('切換帳號前請先登出');
    }
    if (account != null && account != owner) {
      throw StateError('切換帳號前請先登出');
    }
    await coordinator.authenticate(CampusService.sso, (_) async {
      final verified = await sso.verifyIdentity(token, owner);
      coordinator.requireCurrent(captured);
      _persist = () async {
        await vault.write('ssoAccount', owner);
        coordinator.requireCurrent(captured);
        await vault.write('ssoToken', token);
        coordinator.requireCurrent(captured);
        await vault.write('ssoProfile', jsonEncode(verified));
      }();
      await _persist;
      coordinator.requireCurrent(captured);
      account = owner;
      _identityGeneration++;
      _token = token;
      profile = verified;
      isOffline = false;
      ssoNeedsReauthentication = false;
      notifyListeners();
    });
  }

  Future<Uri> academicEntry() async {
    // A freshly verified login is already authoritative. Re-reading storage
    // here can race an earlier startup restore and replace the new session.
    if (!isSignedIn) await restore();
    final captured = coordinator.epoch;
    if (!isSignedIn) throw StateError('請先登入校務帳號');
    final token = _token!;
    final Uri uri;
    try {
      uri = await sso.academicEntry(token, account!);
    } on DioException catch (error) {
      coordinator.requireCurrent(captured);
      if (_token == token && [401, 403].contains(error.response?.statusCode)) {
        _token = null;
        ssoNeedsReauthentication = true;
        isOffline = false;
        notifyListeners();
      }
      rethrow;
    }
    coordinator.requireCurrent(captured);
    return uri;
  }

  Future<void> clearSchedule() async {
    try {
      await _nativeWrite;
    } catch (_) {
      /* Clear failed writes as well. */
    }
    await const ScheduleGateway().clear();
  }

  Future<void> saveSchedule(
    ScheduleSnapshot snapshot, {
    required int epoch,
    required String owner,
  }) async {
    coordinator.requireCurrent(epoch);
    if (!isSignedIn || account != owner) throw SessionChanged();
    final previous = _nativeWrite;
    final task = () async {
      try {
        if (previous != null) await previous;
      } catch (_) {
        /* A new snapshot can replace a failed write. */
      }
      coordinator.requireCurrent(epoch);
      if (account != owner) throw SessionChanged();
      await const ScheduleGateway().saveSnapshot(snapshot);
      coordinator.requireCurrent(epoch);
    }();
    _nativeWrite = task;
    await task;
  }

  Future<void> cacheScheduleRows(
    List<List<String>> rows, {
    required int epoch,
    required String owner,
  }) async {
    coordinator.requireCurrent(epoch);
    if (!isSignedIn || account != owner) throw SessionChanged();
    final cached = CachedSchedule(
      account: owner,
      fetchedAt: DateTime.now().toUtc(),
      rows: rows,
    );
    final previous = _cacheWrite;
    final task = () async {
      try {
        await previous;
      } catch (_) {}
      coordinator.requireCurrent(epoch);
      await vault.write('scheduleCache', jsonEncode(cached.toJson()));
      coordinator.requireCurrent(epoch);
      cachedSchedule = cached;
      notifyListeners();
    }();
    _cacheWrite = task;
    await task;
  }

  Future<void> recoverCleanup() async {
    if (cleanupPending || await vault.read('pendingCleanup') == 'true') {
      await logout();
    }
  }

  Future<void> cacheGraduationData(
    Map<String, dynamic> data, {
    required int epoch,
    required String owner,
  }) async {
    void guard() {
      coordinator.requireCurrent(epoch);
      if (!isSignedIn || account != owner) throw SessionChanged();
    }

    guard();
    final cached = CachedGraduation(
      account: owner,
      fetchedAt: DateTime.now(),
      data: data,
    );
    final previous = _graduationWrite;
    final task = () async {
      try {
        await previous;
      } catch (_) {}
      guard();
      await vault.write('graduationCache', jsonEncode(cached.toJson()));
      guard();
      cachedGraduation = cached;
      _graduationRevision++;
      notifyListeners();
    }();
    _graduationWrite = task;
    await task;
  }

  Future<void> logout() => coordinator.logout(() async {
    cleanupPending = true;
    _identityGeneration++;
    account = null;
    _token = null;
    profile = {};
    _restore = null;
    cachedSchedule = null;
    cachedGraduation = null;
    isOffline = false;
    ssoNeedsReauthentication = false;
    notifyListeners();
    final failures = <Object>[];
    Future<void> attempt(Future<void> Function() action) async {
      try {
        await action();
      } catch (error) {
        failures.add(error);
      }
    }

    await attempt(() => vault.write('pendingCleanup', 'true'));
    try {
      await _persist;
    } catch (_) {
      /* Cleanup removes interrupted writes. */
    }
    try {
      await _nativeWrite;
    } catch (_) {
      /* Clear after any in-flight native write. */
    }
    try {
      await _cacheWrite;
    } catch (_) {}
    try {
      await _graduationWrite;
    } catch (_) {}
    for (final cleanup in List.of(_cleanup)) {
      await attempt(cleanup);
    }
    for (final cleanup
        in platformCleanup ??
            <Future<void> Function()>[
              () => const ScheduleGateway().clear(),
              () async {
                await CookieManager.instance().deleteAllCookies();
              },
              () => WebStorageManager.instance().deleteAllData(),
              () => InAppWebViewController.clearAllCache(),
            ]) {
      await attempt(cleanup);
    }
    await attempt(vault.clear);
    if (failures.isNotEmpty) {
      await vault.write('pendingCleanup', 'true');
      throw StateError('登出清理尚未完成，請重試');
    }
    await vault.write('pendingCleanup', 'false');
    cleanupPending = false;
    notifyListeners();
  });
}
