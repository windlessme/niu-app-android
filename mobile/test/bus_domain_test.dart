import 'package:flutter_test/flutter_test.dart';
import 'package:niu_mobile/features/bus/domain/arrival_rules.dart';
import 'package:niu_mobile/features/bus/domain/models.dart';

void main() {
  final now = DateTime.utc(2026, 9, 29, 8);
  BusArrival arrival({
    int? seconds,
    int? status = 0,
    DateTime? next,
    bool? last,
    String? plate,
  }) => BusArrival(
    source: BusSource.cityBus,
    stopUid: 'synthetic-stop',
    routeUid: 'synthetic-route',
    estimateSeconds: seconds,
    rawStopStatus: status,
    nextBusTime: next,
    isLastBus: last,
    plate: plate,
    timestamp: now,
    fetchedAt: now,
  );
  BusDataEnvelope<BusArrival> envelope(List<BusArrival> items) =>
      BusDataEnvelope.success(
        source: BusSource.cityBus,
        snapshot: BusSnapshot(
          items: items,
          updatedAt: now,
          fetchedAt: now,
          expiresAt: now.add(const Duration(seconds: 30)),
        ),
      );
  BusArrivalClassification classify(BusArrival value) =>
      classifyBusArrivals(envelope([value]), now: now).single;

  test('normal estimate boundaries and upward rounding', () {
    for (final seconds in [0, 1, 59, 60]) {
      expect(
        classify(arrival(seconds: seconds)).state,
        BusArrivalState.arriving,
      );
    }
    for (final seconds in [61, 119]) {
      expect(
        classify(arrival(seconds: seconds)).state,
        BusArrivalState.approaching,
      );
    }
    for (final entry in {120: 2, 121: 3, 180: 3, 181: 4}.entries) {
      final result = classify(arrival(seconds: entry.key));
      expect(result.state, BusArrivalState.estimated);
      expect(result.minutes, entry.value);
    }
  });

  test('missing and negative estimates never become zero', () {
    expect(
      classify(arrival()).unknownReason,
      BusArrivalUnknownReason.missingEstimate,
    );
    expect(
      classify(arrival(seconds: -1)).unknownReason,
      BusArrivalUnknownReason.negativeEstimate,
    );
    for (final seconds in [null, -1]) {
      final next = now.add(const Duration(minutes: 10));
      final result = classify(arrival(seconds: seconds, next: next));
      expect(result.state, BusArrivalState.scheduled);
      expect(result.scheduledAt, next);
    }
    for (final next in [now, now.subtract(const Duration(seconds: 1))]) {
      expect(classify(arrival(next: next)).state, BusArrivalState.unknown);
    }
  });

  test('documented statuses outrank contradictory ETA and next time', () {
    final statuses = {
      1: BusArrivalState.notDeparted,
      2: BusArrivalState.notStopping,
      3: BusArrivalState.stoppedServing,
      4: BusArrivalState.noService,
    };
    for (final entry in statuses.entries) {
      for (final seconds in [null, 0, 180]) {
        expect(
          classify(
            arrival(
              status: entry.key,
              seconds: seconds,
              next: now.add(const Duration(minutes: 5)),
            ),
          ).state,
          entry.value,
        );
      }
    }
    for (final status in [null, -1, 5, 255]) {
      expect(
        classify(
          arrival(
            status: status,
            seconds: 0,
            next: now.add(const Duration(hours: 1)),
          ),
        ).state,
        BusArrivalState.unknown,
      );
    }
    for (final last in [true, false, null]) {
      expect(classify(arrival(last: last)).state, BusArrivalState.unknown);
    }
    expect(
      classify(arrival(seconds: 0, plate: '-1')).unknownReason,
      BusArrivalUnknownReason.noVehicle,
    );
  });

  test('cached old zero is unknown in every nonfresh envelope', () {
    final raw = arrival(seconds: 0);
    final fresh = envelope([raw]);
    for (final cached in [
      fresh.markStale(),
      fresh.refreshing(),
      fresh.failed('offline'),
    ]) {
      final result = classifyBusArrivals(cached, now: now).single;
      expect(result.state, BusArrivalState.unknown);
      expect(result.unknownReason, BusArrivalUnknownReason.stale);
      expect(result.raw, same(raw));
      expect(cached.snapshot, same(fresh.snapshot));
    }
    expect(
      classifyBusArrivals(
        fresh,
        now: now.add(const Duration(seconds: 30)),
      ).single.unknownReason,
      BusArrivalUnknownReason.stale,
    );
  });

  test('successful empty response is distinct from failure and loading', () {
    final empty = envelope([]);
    final failed = BusDataEnvelope<BusArrival>.failure(
      source: BusSource.cityBus,
      error: 'offline',
    );
    expect(empty.items, isEmpty);
    expect(empty.isFreshAt(now), isTrue);
    expect(failed.items, isNull);
    expect(failed.state, BusDataState.error);
    expect(empty.failed('offline').items, isEmpty);
    expect(
      BusDataEnvelope<BusArrival>.loading(source: BusSource.cityBus).items,
      isNull,
    );
    expect(() => empty.items!.add(arrival()), throwsUnsupportedError);
    final input = [arrival()];
    final snapshot = envelope(input);
    input.clear();
    expect(snapshot.items, hasLength(1));
  });

  const stop = StopKey(source: BusSource.cityBus, uid: 'synthetic-stop');
  BusStopRoute occurrence({
    int? direction = 0,
    int sequence = 1,
    String variant = 'variant-a',
    bool circular = false,
  }) => BusStopRoute(
    stop: stop,
    routeUid: 'synthetic-route',
    subrouteUid: variant,
    direction: direction,
    stopSequence: sequence,
    isCircular: circular,
  );
  final route = BusRoute(
    source: BusSource.cityBus,
    uid: 'synthetic-route',
    id: 'local-id',
    name: 'Synthetic route',
    operators: [],
    departure: 'Origin',
    destination: 'End',
  );

  test('source, variant, direction and repeated sequence retain identity', () {
    expect(
      stop,
      isNot(const StopKey(source: BusSource.interCity, uid: 'synthetic-stop')),
    );
    expect(occurrence(), occurrence());
    expect(occurrence().hashCode, occurrence().hashCode);
    expect({
      occurrence(),
      occurrence(variant: 'variant-b'),
      occurrence(direction: 1),
      occurrence(sequence: 9),
      occurrence(direction: 255),
      occurrence(direction: null),
    }, hasLength(6));
  });

  test('direction label precedence, loops and opt-in endpoint fallback', () {
    const subroute = BusSubroute(
      uid: 'variant-a',
      id: 'a',
      name: 'Variant A',
      destination: 'Branch end',
    );
    expect(
      busDirectionLabel(
        occurrence: occurrence(),
        route: route,
        subroute: subroute,
        lastStopName: 'Last stop',
      ).text,
      'Branch end',
    );
    expect(
      busDirectionLabel(
        occurrence: occurrence(variant: 'variant-b'),
        route: route,
        subroute: subroute,
        lastStopName: 'Last stop',
      ).source,
      BusDirectionLabelSource.lastStop,
    );
    expect(
      busDirectionLabel(occurrence: occurrence(), route: route).source,
      BusDirectionLabelSource.unknown,
    );
    for (final direction in [0, 1]) {
      expect(
        busDirectionLabel(
          occurrence: occurrence(direction: direction),
          route: route,
          allowRouteEndpointFallback: true,
        ).text,
        direction == 0 ? 'End' : 'Origin',
      );
    }
    for (final value in [
      occurrence(circular: true),
      occurrence(direction: 2),
      occurrence(direction: 10),
      occurrence(direction: 255),
      occurrence(direction: null),
      occurrence(direction: 99),
    ]) {
      expect(
        busDirectionLabel(
          occurrence: value,
          route: route,
          lastStopName: 'False endpoint',
          allowRouteEndpointFallback: true,
        ).source,
        BusDirectionLabelSource.unknown,
      );
    }
    expect(
      busDirectionLabel(
        occurrence: occurrence(direction: 255),
        route: route,
        subroute: subroute,
      ).source,
      BusDirectionLabelSource.unknown,
    );
  });
}
