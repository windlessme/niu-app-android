import 'dart:convert';
import '../../core/network/school_clients.dart';
import '../../core/session/campus_session.dart';
import 'moodle_repository.dart';

/// One encrypted envelope prevents mixed-account token/private-token pairs.
class MoodleSessionStore {
  MoodleSessionStore(this.owner) {
    owner.registerCleanup(clear);
  }
  final CampusSession owner;
  Future<void>? _write;
  void guard(int epoch, String account) {
    owner.coordinator.requireCurrent(epoch);
    if (!owner.hasLocalAccount ||
        owner.account?.toLowerCase() != account.toLowerCase()) {
      throw StateError('M 園區帳號與校務登入不符');
    }
  }

  Future<void> save(MoodleSession session) async {
    final epoch = owner.coordinator.epoch;
    guard(epoch, session.account);
    final previous = _write;
    final task = () async {
      if (previous != null) {
        try {
          await previous;
        } catch (_) {}
      }
      guard(epoch, session.account);
      await owner.vault.write(
        'moodleSession',
        jsonEncode({
          'account': session.account.toLowerCase(),
          'token': session.token,
          'privateToken': session.privateToken,
          'userId': session.userId,
        }),
      );
      guard(epoch, session.account);
    }();
    _write = task;
    await task;
  }

  Future<MoodleRepository?> restore(MoodleApiClient api) async {
    if (!owner.hasLocalAccount) return null;
    final account = owner.account!;
    final epoch = owner.coordinator.epoch;
    final raw = await owner.vault.read('moodleSession');
    guard(epoch, account);
    if (raw == null || raw.isEmpty) return null;
    final data = object(jsonDecode(raw));
    if (data['account'] != account.toLowerCase()) return null;
    final token = data['token'];
    if (token is! String || token.isEmpty) return null;
    final site = object(
      await api.read(token, 'core_webservice_get_site_info', {}),
    );
    guard(epoch, account);
    if (number(site['userid']) != number(data['userId']) ||
        '${site['username']}'.toLowerCase() != account.toLowerCase()) {
      throw StateError('M 園區登入身分不符');
    }
    return MoodleRepository(
      api,
      MoodleSession(
        account: account,
        token: token,
        userId: number(site['userid']),
        privateToken: data['privateToken'] as String?,
      ),
    )..bindSession(owner);
  }

  Future<void> clear() async {
    try {
      await _write;
    } catch (_) {}
    await owner.vault.write('moodleSession', '');
    owner.unregisterCleanup(clear);
  }

  // Keep cleanup registered while a secure write is in flight.
  Future<void> dispose() async {
    try {
      await _write;
    } catch (_) {}
    owner.unregisterCleanup(clear);
  }
}
