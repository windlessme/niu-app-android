import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/features/schedule_exchange/schedule_exchange_store.dart';
import 'package:niu_mobile/features/schedule_exchange/schedule_share.dart';

import 'schedule_share_test.dart' show iosCode, now;

class MemoryVault implements ExchangeVault {
  final values = <String, String>{};
  Object? failure;
  @override
  Future<String?> read(String key) async {
    if (failure != null) throw failure!;
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    if (failure != null) throw failure!;
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async => values.remove(key);
}

void main() {
  final payload = ScheduleSharePayload.decode(iosCode, now: now);

  test('keeps each account apart, under a key without the username', () async {
    final vault = MemoryVault();
    final store = ScheduleExchangeStore(vault);
    await store.reload('b1234567');
    expect(store.status, ExchangeStatus.ready);
    final id = await store.save('b1234567', payload, now: now);
    expect(id, isNotNull);
    expect(store.schedules.single.displayName, '小明');
    expect(vault.values.keys.single, isNot(contains('b1234567')));

    await store.reload('b7654321');
    expect(store.schedules, isEmpty);
    expect(
      await store.save('b1234567', payload),
      isNull,
      reason: 'another account is signed in',
    );

    await store.reload('b1234567');
    expect(store.schedules.single.payload.slots, payload.slots);
    expect(store.existing(payload)?.id, id);
  });

  test('updates in place or adds a new entry', () async {
    final store = ScheduleExchangeStore(MemoryVault());
    await store.reload('a');
    final first = await store.save('a', payload, now: now);
    final same = await store.save('a', payload, replacing: first, now: now);
    expect(same, first);
    expect(store.schedules, hasLength(1));
    await store.save('a', payload, now: now);
    expect(store.schedules, hasLength(2));
    expect(await store.delete('a', first!), isTrue);
    expect(store.schedules, hasLength(1));
  });

  test('memory changes only after a write succeeds', () async {
    final vault = MemoryVault();
    final store = ScheduleExchangeStore(vault);
    await store.reload('a');
    vault.failure = Exception('disk');
    expect(await store.save('a', payload, now: now), isNull);
    expect(store.schedules, isEmpty);
    final before = store.preferences.shareId;
    expect(await store.resetShareId('a'), isFalse);
    expect(store.preferences.shareId, before);
  });

  test('an unreadable entry is never overwritten until reset', () async {
    final vault = MemoryVault();
    final store = ScheduleExchangeStore(vault);
    vault.values[ScheduleExchangeStore.keyFor('a')] = 'not json';
    await store.reload('a');
    expect(store.status, ExchangeStatus.unreadable);
    expect(await store.save('a', payload, now: now), isNull);
    expect(vault.values.values.single, 'not json');
    await store.resetUnreadable('a');
    expect(store.status, ExchangeStatus.ready);
    expect(vault.values, isEmpty);
  });

  test('removes entries 30 days after their term ends', () async {
    final vault = MemoryVault();
    final store = ScheduleExchangeStore(vault);
    await store.reload('a');
    await store.save('a', payload, now: now);
    final ended = payload.term.endDate;
    await store.reload('a', now: ended.add(const Duration(days: 29)));
    expect(store.schedules.single.isExpired(ended), isTrue);
    await store.reload('a', now: ended.add(const Duration(days: 30)));
    expect(store.schedules, isEmpty);
    final saved = jsonDecode(vault.values.values.single) as Map;
    expect(saved['schedules'], isEmpty);
  });

  test('preferences persist per account', () async {
    final vault = MemoryVault();
    final store = ScheduleExchangeStore(vault);
    await store.reload('a');
    final shareId = store.preferences.shareId;
    await store.updatePreferences(
      'a',
      (p) => p.copyWith(customNickname: '小安', includeRooms: true),
    );
    await store.reload('a');
    expect(store.preferences.customNickname, '小安');
    expect(store.preferences.includeRooms, isTrue);
    expect(store.preferences.shareId, shareId);
    await store.resetShareId('a');
    expect(store.preferences.shareId, isNot(shareId));
  });
}
