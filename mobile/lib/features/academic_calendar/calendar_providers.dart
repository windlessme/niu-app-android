import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

import 'calendar_repository.dart';

class AppCalendarRepository implements CalendarRepository {
  Future<CalendarRepository>? _repository;
  Future<CalendarRepository> _get() => _repository ??= () async {
    try {
      final support = await getApplicationSupportDirectory();
      return CachedCalendarRepository(
        bundle: rootBundle,
        cacheDirectory: Directory('${support.path}/public_calendar'),
      );
    } catch (_) {
      return BundledCalendarRepository(rootBundle);
    }
  }();
  @override
  Future<List<int>> years() async => (await _get()).years();
  @override
  Future<CalendarSnapshot> load(int year) async => (await _get()).load(year);
}

final calendarRepositoryProvider = Provider<CalendarRepository>(
  (ref) => AppCalendarRepository(),
);
final calendarYearsProvider = FutureProvider<List<int>>(
  (ref) => ref.watch(calendarRepositoryProvider).years(),
);
final calendarProvider = FutureProvider.family<CalendarSnapshot, int>(
  (ref, year) => ref.watch(calendarRepositoryProvider).load(year),
);
