/// Bus-domain values only. Wire decoding and freshness policy belong to adapters.
enum BusSource { cityBus, interCity }

final class StopKey {
  const StopKey({required this.source, required this.uid});

  final BusSource source;
  final String uid;

  @override
  bool operator ==(Object other) =>
      other is StopKey && source == other.source && uid == other.uid;

  @override
  int get hashCode => Object.hash(source, uid);
}

final class BusStop {
  const BusStop({
    required this.key,
    required this.id,
    required this.name,
    this.stationUid,
    this.latitude,
    this.longitude,
    this.bearing,
  });

  final StopKey key;
  String get uid => key.uid;
  final String id;
  final String name;

  /// Optional normalized station association, not an inferred stop identity.
  /// V2 StationID/StationGroupID must not be relabelled as a UID blindly.
  final String? stationUid;
  final double? latitude;
  final double? longitude;
  final String? bearing;
}

final class BusOperator {
  const BusOperator({required this.id, required this.name});
  final String id;
  final String name;
}

final class BusSubroute {
  const BusSubroute({
    required this.uid,
    required this.id,
    required this.name,
    this.departure,
    this.destination,
  });

  final String uid;
  final String id;
  final String name;

  /// Direction-specific endpoints, when supplied by a verified adapter.
  final String? departure;
  final String? destination;
}

final class BusRoute {
  BusRoute({
    required this.source,
    required this.uid,
    required this.id,
    required this.name,
    required List<BusOperator> operators,
    this.departure,
    this.destination,
    List<BusSubroute> subroutes = const [],
  }) : operators = List.unmodifiable(operators),
       subroutes = List.unmodifiable(subroutes);

  final BusSource source;
  final String uid;
  final String id;
  final String name;
  final List<BusOperator> operators;
  final String? departure;
  final String? destination;
  final List<BusSubroute> subroutes;
}

/// One occurrence of a stop on a route variant, not just route membership.
final class BusStopRoute {
  const BusStopRoute({
    required this.stop,
    required this.routeUid,
    required this.subrouteUid,
    required this.direction,
    required this.stopSequence,
    required this.isCircular,
  });

  final StopKey stop;
  final String routeUid;
  final String? subrouteUid;

  /// Raw StopOfRoute direction: 0/1/2/10/255, null, or future values.
  /// This is not a stop bearing or the vehicle direction in an ETA record.
  final int? direction;
  final int stopSequence;
  final bool isCircular;

  /// Sequence preserves repeated visits to the same stop on a circular route.
  (StopKey, String, String?, int?, int) get identity =>
      (stop, routeUid, subrouteUid, direction, stopSequence);

  @override
  bool operator ==(Object other) =>
      other is BusStopRoute && identity == other.identity;

  @override
  int get hashCode => identity.hashCode;
}

/// Raw normalized N1 data. Missing values are never replaced with zero.
final class BusArrival {
  const BusArrival({
    required this.source,
    required this.timestamp,
    required this.fetchedAt,
    this.stopUid,
    this.routeUid,
    this.subrouteUid,
    this.direction,
    this.stopSequence,
    this.estimateSeconds,
    this.rawStopStatus,
    this.nextBusTime,
    this.isLastBus,
    this.plate,
    this.dataTime,
  });

  final BusSource source;
  final String? stopUid;
  final String? routeUid;
  final String? subrouteUid;
  final int? direction;
  final int? stopSequence;
  final int? estimateSeconds;
  final int? rawStopStatus;
  final DateTime? nextBusTime;
  final bool? isLastBus;
  final String? plate;

  /// TDX UpdateTime, not necessarily the prediction calculation time.
  final DateTime timestamp;
  final DateTime? dataTime;
  final DateTime fetchedAt;
}

enum BusDataState { fresh, stale, loading, error }

/// An immutable successful snapshot, including a successful empty list.
final class BusSnapshot<T> {
  BusSnapshot({
    required List<T> items,
    required this.updatedAt,
    required this.fetchedAt,
    required this.expiresAt,
  }) : items = List.unmodifiable(items);

  final List<T> items;
  final DateTime? updatedAt;
  final DateTime fetchedAt;
  final DateTime expiresAt;
}

/// Null snapshot means no successful response; [] means successful empty data.
/// Failed/loading refreshes retain the prior snapshot and its original times.
final class BusDataEnvelope<T> {
  const BusDataEnvelope._({
    required this.source,
    required this.state,
    this.snapshot,
    this.error,
  });

  factory BusDataEnvelope.success({
    required BusSource source,
    required BusSnapshot<T> snapshot,
  }) => BusDataEnvelope._(
    source: source,
    state: BusDataState.fresh,
    snapshot: snapshot,
  );

  factory BusDataEnvelope.loading({required BusSource source}) =>
      BusDataEnvelope._(source: source, state: BusDataState.loading);

  factory BusDataEnvelope.failure({
    required BusSource source,
    required Object error,
  }) => BusDataEnvelope._(
    source: source,
    state: BusDataState.error,
    error: error,
  );

  final BusSource source;
  final BusDataState state;
  final BusSnapshot<T>? snapshot;
  final Object? error;

  List<T>? get items => snapshot?.items;
  DateTime? get updatedAt => snapshot?.updatedAt;
  DateTime? get fetchedAt => snapshot?.fetchedAt;
  DateTime? get expiresAt => snapshot?.expiresAt;

  bool isFreshAt(DateTime now) =>
      state == BusDataState.fresh &&
      snapshot != null &&
      now.isBefore(snapshot!.expiresAt);

  BusDataEnvelope<T> refreshing() => BusDataEnvelope._(
    source: source,
    state: BusDataState.loading,
    snapshot: snapshot,
  );

  BusDataEnvelope<T> failed(Object error) => BusDataEnvelope._(
    source: source,
    state: BusDataState.error,
    snapshot: snapshot,
    error: error,
  );

  BusDataEnvelope<T> markStale() => BusDataEnvelope._(
    source: source,
    state: BusDataState.stale,
    snapshot: snapshot,
    error: error,
  );
}
