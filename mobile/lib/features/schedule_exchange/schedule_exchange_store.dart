import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'schedule_share.dart';

/// A classmate's timetable received by QR code.
class ExchangedSchedule {
  const ExchangedSchedule({
    required this.id,
    required this.payload,
    required this.importedAt,
  });
  final String id;
  final ScheduleSharePayload payload;
  final DateTime importedAt;

  String get displayName =>
      payload.nickname.isEmpty ? '未命名同學' : payload.nickname;

  bool isExpired(DateTime now) => !payload.term.endDate.isAfter(now);

  /// Expired entries stay visible this long, so a wrong term is noticed
  /// before the entry disappears.
  static const deletionGrace = Duration(days: 30);
  bool shouldDelete(DateTime now) =>
      !payload.term.endDate.add(deletionGrace).isAfter(now);

  Map<String, Object> toJson() => {
    'id': id,
    'importedAt': importedAt.millisecondsSinceEpoch,
    'payload': payload.toWire(),
  };

  static ExchangedSchedule? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'], at = json['importedAt'], wire = json['payload'];
    if (id is! String || at is! int || wire is! Map) return null;
    try {
      return ExchangedSchedule(
        id: id,
        payload: ScheduleSharePayload.fromWire(wire),
        importedAt: DateTime.fromMillisecondsSinceEpoch(at, isUtc: true),
      );
    } on ScheduleShareError {
      return null;
    }
  }
}

/// Per-account sharing choices.
class ScheduleSharePreferences {
  const ScheduleSharePreferences({
    required this.shareId,
    this.useRealName = false,
    this.customNickname = '',
    this.includeRooms = false,
    this.includeTeachers = false,
  });
  final String shareId;
  final bool useRealName;
  final String customNickname;
  final bool includeRooms, includeTeachers;

  ScheduleSharePreferences copyWith({
    String? shareId,
    bool? useRealName,
    String? customNickname,
    bool? includeRooms,
    bool? includeTeachers,
  }) => ScheduleSharePreferences(
    shareId: shareId ?? this.shareId,
    useRealName: useRealName ?? this.useRealName,
    customNickname: customNickname ?? this.customNickname,
    includeRooms: includeRooms ?? this.includeRooms,
    includeTeachers: includeTeachers ?? this.includeTeachers,
  );

  Map<String, Object> toJson() => {
    'shareId': shareId,
    'useRealName': useRealName,
    'customNickname': customNickname,
    'includeRooms': includeRooms,
    'includeTeachers': includeTeachers,
  };

  factory ScheduleSharePreferences.fromJson(Object? json) {
    final map = json is Map ? json : const {};
    final id = map['shareId'];
    return ScheduleSharePreferences(
      shareId: id is String && id.isNotEmpty
          ? id
          : ScheduleSharePayload.newShareId(),
      useRealName: map['useRealName'] == true,
      customNickname: ScheduleSharePayload.cleanNickname(
        '${map['customNickname'] ?? ''}',
      ),
      includeRooms: map['includeRooms'] == true,
      includeTeachers: map['includeTeachers'] == true,
    );
  }
}

abstract class ExchangeVault {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// Android Keystore-backed storage, excluded from backups by the manifest.
class DeviceExchangeVault implements ExchangeVault {
  const DeviceExchangeVault([this.storage = const FlutterSecureStorage()]);
  final FlutterSecureStorage storage;
  @override
  Future<String?> read(String key) => storage.read(key: key);
  @override
  Future<void> write(String key, String value) =>
      storage.write(key: key, value: value);
  @override
  Future<void> delete(String key) => storage.delete(key: key);
}

enum ExchangeStatus { signedOut, loading, ready, unreadable }

/// Classmates' timetables are other people's personal data. Each account's
/// list is one encrypted entry, named by a hash so the key does not reveal
/// the username; nothing is uploaded. Logging out keeps the entry, as on
/// iOS, and a write changes memory only after it succeeded.
class ScheduleExchangeStore extends ChangeNotifier {
  ScheduleExchangeStore(this.vault);
  static final instance = ScheduleExchangeStore(const DeviceExchangeVault());
  final ExchangeVault vault;

  String? _account;
  ExchangeStatus _status = ExchangeStatus.signedOut;
  List<ExchangedSchedule> _schedules = const [];
  ScheduleSharePreferences? _preferences;
  Future<void> _work = Future.value();
  int _generation = 0;

  String? get account => _account;
  ExchangeStatus get status => _status;
  List<ExchangedSchedule> get schedules => _schedules;
  ScheduleSharePreferences get preferences => _preferences ??=
      ScheduleSharePreferences(shareId: ScheduleSharePayload.newShareId());

  /// Whether the store holds [account]'s data and can change it.
  bool isReadyFor(String? account) =>
      account != null && account == _account && _status == ExchangeStatus.ready;

  static String keyFor(String account) =>
      'niu.scheduleExchange.${sha256.convert(utf8.encode(account))}';

  /// Shows [account]'s list, reading it once per sign-in; null clears memory.
  void bind(String? account) {
    if (account == _account && _status != ExchangeStatus.signedOut) return;
    unawaited(reload(account));
  }

  /// Re-reads [account]'s list and removes entries past their grace period.
  Future<void> reload(String? account, {DateTime? now}) {
    final generation = ++_generation;
    _account = account;
    _schedules = const [];
    _preferences = null;
    _status = account == null
        ? ExchangeStatus.signedOut
        : ExchangeStatus.loading;
    notifyListeners();
    if (account == null) return Future.value();
    return _serial(() async {
      final Map<Object?, Object?> data;
      try {
        final raw = await vault.read(keyFor(account));
        final decoded = raw == null ? const {} : jsonDecode(raw);
        if (decoded is! Map) throw const FormatException();
        data = decoded;
      } catch (_) {
        if (generation == _generation) {
          _status = ExchangeStatus.unreadable;
          notifyListeners();
        }
        return;
      }
      if (generation != _generation) return;
      final list = [
        for (final entry
            in data['schedules'] is List ? data['schedules'] as List : const [])
          ?ExchangedSchedule.fromJson(entry),
      ];
      _preferences = ScheduleSharePreferences.fromJson(data['preferences']);
      _schedules = List.unmodifiable(list);
      _status = ExchangeStatus.ready;
      notifyListeners();
      final at = now ?? DateTime.now();
      if (list.any((e) => e.shouldDelete(at))) {
        // On failure the entries stay and cleanup runs on the next reload.
        await _persist(
          account,
          generation,
          schedules: [...list.where((e) => !e.shouldDelete(at))],
        );
      }
    });
  }

  Future<T> _serial<T>(Future<T> Function() task) {
    final result = _work.then((_) => task());
    _work = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<bool> _persist(
    String account,
    int generation, {
    List<ExchangedSchedule>? schedules,
    ScheduleSharePreferences? preferences,
  }) async {
    if (generation != _generation || account != _account) return false;
    final list = schedules ?? _schedules;
    final prefs = preferences ?? this.preferences;
    try {
      await vault.write(
        keyFor(account),
        jsonEncode({
          'preferences': prefs.toJson(),
          'schedules': [for (final e in list) e.toJson()],
        }),
      );
    } catch (_) {
      return false;
    }
    if (generation != _generation) return false;
    _schedules = List.unmodifiable(list);
    _preferences = prefs;
    notifyListeners();
    return true;
  }

  /// The saved entry a payload would update: same sharer ID and term. The ID
  /// proves nothing, so callers ask before overwriting.
  ExchangedSchedule? existing(ScheduleSharePayload payload) => _schedules
      .where(
        (e) =>
            e.payload.shareId.toUpperCase() == payload.shareId.toUpperCase() &&
            e.payload.term == payload.term,
      )
      .firstOrNull;

  /// The saved entry's ID, or null when nothing was written.
  Future<String?> save(
    String account,
    ScheduleSharePayload payload, {
    String? replacing,
    DateTime? now,
  }) {
    final generation = _generation;
    return _serial(() async {
      if (!isReadyFor(account)) return null;
      final at = (now ?? DateTime.now()).toUtc();
      final list = [..._schedules];
      final index = replacing == null
          ? -1
          : list.indexWhere((e) => e.id == replacing);
      final id = index < 0 ? ScheduleSharePayload.newShareId() : replacing!;
      final entry = ExchangedSchedule(id: id, payload: payload, importedAt: at);
      index < 0 ? list.add(entry) : list[index] = entry;
      return await _persist(account, generation, schedules: list) ? id : null;
    });
  }

  Future<bool> delete(String account, String id) {
    final generation = _generation;
    return _serial(() async {
      if (!isReadyFor(account)) return false;
      return _persist(
        account,
        generation,
        schedules: [..._schedules.where((e) => e.id != id)],
      );
    });
  }

  Future<bool> updatePreferences(
    String account,
    ScheduleSharePreferences Function(ScheduleSharePreferences) change,
  ) {
    final generation = _generation;
    return _serial(() async {
      if (!isReadyFor(account)) return false;
      return _persist(account, generation, preferences: change(preferences));
    });
  }

  /// Classmates who saved the old code can no longer match new codes to it.
  Future<bool> resetShareId(String account) => updatePreferences(
    account,
    (p) => p.copyWith(shareId: ScheduleSharePayload.newShareId()),
  );

  /// Removes an entry that can no longer be decrypted, after the user agrees.
  Future<void> resetUnreadable(String account) async {
    if (account != _account || _status != ExchangeStatus.unreadable) return;
    try {
      await vault.delete(keyFor(account));
    } catch (_) {
      return;
    }
    await reload(account);
  }
}
