import 'dart:async';
import 'dart:convert';

import 'campus_session.dart';

/// A school page as last read, shown while a fresh copy loads.
class CachedSnapshot {
  const CachedSnapshot(this.updatedAt, this.data);
  final DateTime updatedAt;
  final Map<String, dynamic> data;
}

/// Last-read school pages (grades, registration), scoped to the account in
/// the vault and removed with it at logout. Keys name the page, e.g.
/// `grades.history`.
class PortalSnapshotCache {
  PortalSnapshotCache._(this.session) {
    session.registerCleanup(_drain);
  }

  static final _instances = Expando<PortalSnapshotCache>();

  /// One cache per session, so writes from different pages queue up.
  static PortalSnapshotCache of(CampusSession session) =>
      _instances[session] ??= PortalSnapshotCache._(session);

  final CampusSession session;
  Future<void>? _write;

  Future<CachedSnapshot?> read(String key) async {
    final owner = session.account;
    if (owner == null || session.isDemo) return null;
    try {
      final entry = (await _load(owner))[key];
      if (entry is! Map || session.account != owner) return null;
      final updatedAt = DateTime.tryParse('${entry['updatedAt']}');
      final data = entry['data'];
      if (updatedAt == null || data is! Map<String, dynamic>) return null;
      return CachedSnapshot(updatedAt, data);
    } catch (_) {
      return null;
    }
  }

  /// Saves [data] for [owner] unless the session moved on since [epoch].
  Future<void> write(
    String key,
    Map<String, dynamic> data, {
    required int epoch,
    required String owner,
    DateTime? now,
  }) {
    final previous = _write;
    final task = () async {
      try {
        await previous;
      } catch (_) {}
      _guard(epoch, owner);
      final snapshots = await _load(owner);
      snapshots[key] = {
        'updatedAt': (now ?? DateTime.now()).toUtc().toIso8601String(),
        'data': data,
      };
      final raw = jsonEncode({
        'version': 1,
        'account': owner,
        'snapshots': snapshots,
      });
      _guard(epoch, owner);
      await session.vault.write('portalCache', raw);
    }();
    _write = task;
    return task;
  }

  Future<Map<String, dynamic>> _load(String owner) async {
    try {
      final json = jsonDecode(await session.vault.read('portalCache') ?? '');
      if (json is Map &&
          json['version'] == 1 &&
          json['account'] == owner &&
          json['snapshots'] is Map) {
        return Map<String, dynamic>.from(json['snapshots'] as Map);
      }
    } catch (_) {}
    return {};
  }

  void _guard(int epoch, String owner) {
    session.coordinator.requireCurrent(epoch);
    if (!session.hasLocalAccount || session.account != owner) {
      throw StateError('Session changed');
    }
  }

  // Logout clears the vault; let an in-flight write land (or fail) first.
  Future<void> _drain() async {
    try {
      await _write;
    } catch (_) {}
  }
}
