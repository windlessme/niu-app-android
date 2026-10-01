enum CampusService { sso, academic, moodleApi, moodleWeb, library, mail }

enum ServiceStatus { unknown, authenticating, valid, interactionRequired }

class SessionChanged implements Exception {}

/// Serializes authentication per service and invalidates work across logout.
class SessionCoordinator {
  int _epoch = 0;
  bool _clearing = false;
  Future<void>? _cleanup;
  final _pending = <CampusService, Future<void>>{};
  final _status = <CampusService, ServiceStatus>{};

  int get epoch => _epoch;
  ServiceStatus status(CampusService service) =>
      _status[service] ?? ServiceStatus.unknown;

  void requireCurrent(int capturedEpoch) {
    if (_clearing || capturedEpoch != _epoch) throw SessionChanged();
  }

  Future<void> authenticate(
    CampusService service,
    Future<void> Function(int epoch) action,
  ) {
    if (_clearing) return Future.error(SessionChanged());
    final pending = _pending[service];
    if (pending != null) return pending;
    final captured = _epoch;
    _status[service] = ServiceStatus.authenticating;
    final task = Future<void>(() async {
      try {
        requireCurrent(captured);
        await action(captured);
        requireCurrent(captured);
        _status[service] = ServiceStatus.valid;
      } catch (_) {
        if (captured == _epoch) {
          _status[service] = ServiceStatus.interactionRequired;
        }
        rethrow;
      } finally {
        if (captured == _epoch) _pending.remove(service);
      }
    });
    _pending[service] = task;
    return task;
  }

  Future<void> logout(Future<void> Function() clearPersonalData) {
    if (_cleanup != null) return _cleanup!;
    if (_clearing) return retryCleanup(clearPersonalData);
    _clearing = true;
    _epoch++;
    _pending.clear();
    _status.clear();
    return _runCleanup(clearPersonalData);
  }

  Future<void> retryCleanup(Future<void> Function() clearPersonalData) {
    if (_cleanup != null) return _cleanup!;
    if (!_clearing) throw StateError('No cleanup pending');
    return _runCleanup(clearPersonalData);
  }

  Future<void> _runCleanup(Future<void> Function() clearPersonalData) {
    final task = Future<void>(() async {
      try {
        await clearPersonalData();
        _clearing = false;
      } finally {
        // Failure keeps authentication blocked, but permits a cleanup retry.
        _cleanup = null;
      }
    });
    _cleanup = task;
    return task;
  }
}
