import 'models.dart';

enum BusArrivalState {
  arriving,
  approaching,
  estimated,
  scheduled,
  notDeparted,
  notStopping,
  stoppedServing,
  noService,
  suspended,
  unknown,
}

enum BusArrivalUnknownReason {
  stale,
  missingIdentity,
  missingStatus,
  unsupportedStatus,
  missingEstimate,
  negativeEstimate,
  noVehicle,
}

final class BusArrivalClassification {
  const BusArrivalClassification({
    required this.raw,
    required this.state,
    this.minutes,
    this.scheduledAt,
    this.unknownReason,
  });

  final BusArrival raw;
  final BusArrivalState state;
  final int? minutes;
  final DateTime? scheduledAt;
  final BusArrivalUnknownReason? unknownReason;
}

/// Classifies the entire snapshot so stale cached estimates cannot claim live
/// arrivals. The caller supplies time; there is no hidden clock or network I/O.
List<BusArrivalClassification> classifyBusArrivals(
  BusDataEnvelope<BusArrival> envelope, {
  required DateTime now,
}) => List.unmodifiable([
  for (final arrival in envelope.items ?? const <BusArrival>[])
    classifyBusArrival(arrival, envelope: envelope, now: now),
]);

BusArrivalClassification classifyBusArrival(
  BusArrival arrival, {
  required BusDataEnvelope<BusArrival> envelope,
  required DateTime now,
}) {
  BusArrivalClassification state(BusArrivalState value) =>
      BusArrivalClassification(raw: arrival, state: value);
  BusArrivalClassification unknown(BusArrivalUnknownReason reason) =>
      BusArrivalClassification(
        raw: arrival,
        state: BusArrivalState.unknown,
        unknownReason: reason,
      );

  if (!envelope.isFreshAt(now)) {
    return unknown(BusArrivalUnknownReason.stale);
  }
  if (arrival.source != envelope.source ||
      arrival.stopUid == null ||
      arrival.stopUid!.trim().isEmpty ||
      arrival.routeUid == null ||
      arrival.routeUid!.trim().isEmpty) {
    return unknown(BusArrivalUnknownReason.missingIdentity);
  }

  // Documented v2 StopStatus. Non-normal statuses outrank all timing fields.
  switch (arrival.rawStopStatus) {
    case 1:
      return state(BusArrivalState.notDeparted);
    case 2:
      return state(BusArrivalState.notStopping);
    case 3:
      return state(BusArrivalState.stoppedServing);
    case 4:
      return state(BusArrivalState.noService);
    case null:
      return unknown(BusArrivalUnknownReason.missingStatus);
    case 0:
      break;
    default:
      return unknown(BusArrivalUnknownReason.unsupportedStatus);
  }

  final seconds = arrival.estimateSeconds;
  if (seconds == null || seconds < 0 || arrival.plate == '-1') {
    final next = arrival.nextBusTime;
    if (next != null && next.isAfter(now)) {
      return BusArrivalClassification(
        raw: arrival,
        state: BusArrivalState.scheduled,
        scheduledAt: next,
      );
    }
    return unknown(
      arrival.plate == '-1'
          ? BusArrivalUnknownReason.noVehicle
          : seconds == null
          ? BusArrivalUnknownReason.missingEstimate
          : BusArrivalUnknownReason.negativeEstimate,
    );
  }
  if (seconds <= 60) return state(BusArrivalState.arriving);
  if (seconds <= 119) return state(BusArrivalState.approaching);
  return BusArrivalClassification(
    raw: arrival,
    state: BusArrivalState.estimated,
    minutes: (seconds + 59) ~/ 60,
  );
}

enum BusDirectionLabelSource {
  subrouteDestination,
  lastStop,
  routeEndpoint,
  unknown,
}

final class BusDirectionLabel {
  const BusDirectionLabel({required this.text, required this.source});
  final String text;
  final BusDirectionLabelSource source;
}

/// Metadata must describe the same route variant/ordered StopOfRoute pattern.
/// Route endpoint fallback is opt-in because 0/1 is not a compass direction.
BusDirectionLabel busDirectionLabel({
  required BusStopRoute occurrence,
  required BusRoute route,
  BusSubroute? subroute,
  String? lastStopName,
  bool allowRouteEndpointFallback = false,
  String unknownLabel = '方向未知',
}) {
  final unknown = BusDirectionLabel(
    text: unknownLabel,
    source: BusDirectionLabelSource.unknown,
  );
  String? nonempty(String? value) =>
      value == null || value.trim().isEmpty ? null : value.trim();

  if (route.source != occurrence.stop.source ||
      route.uid != occurrence.routeUid ||
      !const [0, 1, 2, 10].contains(occurrence.direction)) {
    return unknown;
  }
  final destination = subroute?.uid == occurrence.subrouteUid
      ? nonempty(subroute?.destination)
      : null;
  if (destination != null) {
    return BusDirectionLabel(
      text: destination,
      source: BusDirectionLabelSource.subrouteDestination,
    );
  }
  if (occurrence.isCircular ||
      occurrence.direction == 2 ||
      occurrence.direction == 10) {
    return unknown;
  }
  final last = nonempty(lastStopName);
  if (last != null) {
    return BusDirectionLabel(
      text: last,
      source: BusDirectionLabelSource.lastStop,
    );
  }
  final departure = nonempty(route.departure);
  final end = nonempty(route.destination);
  if (allowRouteEndpointFallback &&
      departure != null &&
      end != null &&
      departure != end) {
    return BusDirectionLabel(
      text: occurrence.direction == 0 ? end : departure,
      source: BusDirectionLabelSource.routeEndpoint,
    );
  }
  return unknown;
}
