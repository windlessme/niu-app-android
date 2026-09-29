import 'dart:convert';
import '../../core/session/campus_session.dart';
import 'school_login_capture.dart';

/// One serialized secure-storage envelope per session. The lifetime deliberately
/// outlives LoginScreen: logout must drain writes even after route disposal.
class RememberSchoolLogin {
  RememberSchoolLogin._(this.session) {
    session.registerCleanup(_cleanup);
  }

  static final _instances = Expando<RememberSchoolLogin>();
  static RememberSchoolLogin forSession(CampusSession session) =>
      _instances[session] ??= RememberSchoolLogin._(session);
  static const key = 'rememberedSchoolLogin';
  final CampusSession session;
  Future<void> _pending = Future.value();
  int revision = 0;
  bool enabled = false;

  Future<void> _enqueue(Future<void> Function() operation) {
    final task = _pending.then((_) => operation());
    _pending = task.catchError((Object _) {});
    return task;
  }

  Future<SubmittedSchoolCredentials?> restore() async {
    final generation = revision;
    final epoch = session.coordinator.epoch;
    await _pending;
    final raw = await session.vault.read(key);
    session.coordinator.requireCurrent(epoch);
    if (generation != revision || session.cleanupPending) return null;
    try {
      final data = jsonDecode(raw ?? '') as Map;
      final credentials = SubmittedSchoolCredentials.fromMessage(
        {...data, 'capability': 'vault'},
        page: Uri.parse('https://ccsys1.niu.edu.tw/SSO/login'),
        capability: 'vault',
      );
      if (data['version'] != 1 ||
          credentials == null ||
          (session.account != null && session.account != credentials.account)) {
        return null;
      }
      enabled = true;
      return credentials;
    } catch (_) {
      return null;
    }
  }

  Future<void> setEnabled(bool value) {
    revision++;
    enabled = value;
    if (value) return Future.value();
    // Empty tombstone contains no credentials; serialized behind any old write.
    return _enqueue(() => session.vault.write(key, ''));
  }

  Future<void> forget() => setEnabled(false);

  Future<void> saveVerified(
    SubmittedSchoolCredentials credentials, {
    required int epoch,
    required int consentRevision,
  }) => _enqueue(() async {
    session.coordinator.requireCurrent(epoch);
    if (!enabled ||
        revision != consentRevision ||
        !session.isSignedIn ||
        session.account != credentials.account ||
        session.cleanupPending) {
      return;
    }
    await session.vault.write(
      key,
      jsonEncode({
        'version': 1,
        'account': credentials.account,
        'password': credentials.password,
      }),
    );
  });

  Future<void> _cleanup() async {
    revision++;
    enabled = false;
    await _pending;
    // CampusSession calls vault.clear after all registered cleanup completes.
  }
}
