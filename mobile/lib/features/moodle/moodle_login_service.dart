import '../../core/network/school_clients.dart';
import '../../core/session/campus_session.dart';
import '../../core/session/session_coordinator.dart';
import 'moodle_repository.dart';
import 'moodle_session_store.dart';

/// Shared by visible SSO login, the Moodle tab, and quick attendance.
/// Only the encrypted token envelope survives a call; passwords are never saved.
class MoodleLoginService {
  MoodleLoginService(this.owner, {MoodleApiClient? api})
    : api = api ?? MoodleApiClient(schoolClient('https://euni.niu.edu.tw'));
  final CampusSession owner;
  final MoodleApiClient api;

  void _guardPasswordHandoff(int epoch, String account) {
    owner.coordinator.requireCurrent(epoch);
    if (!owner.hasLocalAccount ||
        !owner.isSignedIn ||
        owner.account?.toLowerCase() != account) {
      throw StateError('請先驗證同一個校務帳號，再建立 M 園區登入');
    }
  }

  Future<MoodleRepository?> restore() async {
    final store = MoodleSessionStore(owner);
    try {
      return await store.restore(api);
    } finally {
      await store.dispose();
    }
  }

  Future<MoodleRepository> establish({
    required String account,
    required String password,
    required int epoch,
  }) async {
    final store = MoodleSessionStore(owner);
    final normalized = account.trim().toLowerCase();
    try {
      _guardPasswordHandoff(epoch, normalized);
      await owner.coordinator.authenticate(CampusService.moodleApi, (_) async {
        _guardPasswordHandoff(epoch, normalized);
        final result = await MoodleRepository.login(api, normalized, password);
        _guardPasswordHandoff(epoch, normalized);
        await store.save(result.session);
      });
      store.guard(epoch, normalized);
      final result = await store.restore(api);
      if (result == null) throw StateError('M 園區登入尚未建立');
      return result;
    } finally {
      await store.dispose();
    }
  }
}
