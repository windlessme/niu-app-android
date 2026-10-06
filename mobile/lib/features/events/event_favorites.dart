import 'dart:convert';

import '../../core/session/campus_session.dart';

/// Starred events, on this device only. Kept in the session's secure storage
/// with the account they belong to, so logging out (which clears that store)
/// removes them and another account never sees them.
class EventFavorites {
  EventFavorites(this.session);
  final CampusSession session;
  static const key = 'eventFavorites';

  Future<Set<String>> load() async {
    final owner = session.account;
    if (owner == null) return {};
    try {
      final raw = await session.vault.read(key);
      final data = raw == null ? null : jsonDecode(raw);
      if (data is Map && data['account'] == owner && data['ids'] is List) {
        return {
          for (final id in data['ids'] as List)
            if (id is String && id.isNotEmpty) id,
        };
      }
    } catch (_) {
      // A damaged copy counts as no favorites.
    }
    return {};
  }

  /// Adds or removes [ids] and returns the saved set.
  Future<Set<String>> set(
    Iterable<String> ids, {
    required bool favorite,
  }) async {
    final owner = session.account;
    if (owner == null) return {};
    final epoch = session.coordinator.epoch;
    final next = await load();
    final changes = ids.where((id) => id.isNotEmpty);
    favorite ? next.addAll(changes) : next.removeAll(changes);
    // Never write one account's stars after a logout or switch.
    session.coordinator.requireCurrent(epoch);
    if (session.account != owner) return {};
    await session.vault.write(
      key,
      jsonEncode({'account': owner, 'ids': next.toList()..sort()}),
    );
    return next;
  }
}
