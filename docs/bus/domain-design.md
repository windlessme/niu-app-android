# Bus domain — Phase 1

The pure Dart contract lives in `mobile/lib/features/bus/domain/models.dart` and
`arrival_rules.dart`. It has no Flutter, network, storage or third-party imports.
`mobile/test/bus_domain_test.dart` uses the project's existing test runner.
All test names and IDs are synthetic; the domain contains no stop catalogue.

## Identity and metadata

- `BusSource.cityBus` and `interCity` scope all identities. `StopKey` is source +
  StopUID, never a display name, station group, local StopID or coordinate.
- `BusStop` retains UID, local ID, name, optional station association, optional
  latitude/longitude and geographic bearing. It has no route direction.
  `stationUid` is a normalized association only: v2 StationID and StationGroupID
  are not implicitly UIDs. Adapters must establish an actual join or leave it null.
- `BusRoute` retains UID, local ID, name, operators, endpoints and subroutes.
  Optional subroute endpoints must be verified, direction-specific metadata.
- `BusStopRoute` is an occurrence, keyed by source/stop UID, route UID,
  subroute UID, raw nullable direction and StopSequence. A loop visiting one stop
  twice has two identities. Direction 255 and unfamiliar values remain intact.
  The circular flag is pattern metadata, not a reason to merge occurrences.
- Arrival identifiers remain nullable because the documented v2 N1 schema allows
  them to be absent. Missing stop/route identity prevents a live classification.
  Vehicle Direction in N1 must not be blindly joined to StopOfRoute Direction;
  the upstream contract explicitly distinguishes them.

## Arrival rules

`BusArrival` retains nullable EstimateTime seconds, raw StopStatus, NextBusTime,
IsLastBus boolean, plate, UpdateTime (`timestamp`), DataTime and local fetchedAt.
Null seconds are not zero. UpdateTime is not the calculation time. No raw field
is overwritten by classification; each result references its original arrival.

Classification first checks the envelope's freshness, then usable identity,
then StopStatus. Non-normal and unknown statuses take precedence over all timing
fields, including future NextBusTime:

| Raw StopStatus | Domain state | Meaning |
| --- | --- | --- |
| 0 | timing rules below | Normal |
| 1 | notDeparted | 尚未發車; positive seconds may describe departure, not arrival |
| 2 | notStopping | 交管不停靠 at this stop |
| 3 | stoppedServing | 末班車已過; last bus has passed |
| 4 | noService | 今日未營運; no operation today |
| null / other | unknown | Missing or unsupported status |

For status 0, seconds 0–60 mean arriving, 61–119 approaching, and >=120 estimated
with minutes rounded **up**. Missing/negative seconds mean unknown unless
NextBusTime is strictly in the future; then the state is scheduled and exposes
that absolute timestamp, never a live countdown. Plate `-1` similarly prevents
a live estimate. Scheduled here means separately supplied next-arrival information,
not an assertion that NextBusTime is an origin departure or timetable entry.
An expired or exactly-now NextBusTime is not promoted to arriving.

`suspended` is reserved for future explicitly supported evidence. No documented
v2 StopStatus currently maps to it. Empty arrays, null estimates, unknown enums,
IsLastBus or missing records never imply suspension or no service.

## Data envelope and freshness

`BusDataEnvelope<T>` holds source, fresh/stale/loading/error state and an optional
immutable successful `BusSnapshot<T>`. A snapshot owns items, source updatedAt,
local fetchedAt and expiresAt. A successful empty list is a real snapshot; a
failure before any success has no snapshot. `refreshing()`, `failed(error)` and
`markStale()` preserve cached data and its original timestamps. Lists are copied
and unmodifiable. Creating a successful envelope replaces a snapshot explicitly.

`isFreshAt(now)` requires state fresh and `now < expiresAt`; expiry is exclusive.
Both arrival-classification functions require the envelope and an explicit clock.
Stale, loading, failed and expired snapshots classify as unknown with reason stale,
including an old zero-second arrival and old no-service statuses. Raw records
remain available. This deliberately conservative Phase 1 policy also suppresses
live claims while refreshing a previously successful snapshot.

The adapter owns TTL/source freshness policy and must mark old upstream data
stale or expire it appropriately: a freshly fetched response is not necessarily
a fresh prediction. No TTL, countdown adjustment, polling or network policy is
implemented here. `classifyBusArrivals` returns no classified rows for either
missing or empty data; consumers must inspect the envelope to distinguish them.

## Direction labels

`busDirectionLabel` validates route/source and preserves null, 255 and unsupported
directions as unknown, even if endpoints exist. For supported directions it
prefers a matching subroute's verified destination. Otherwise it uses the
pattern's last stop **only for noncircular patterns**, then an explicitly enabled
Route endpoint fallback for 0/1. Both route endpoints must be nonblank and distinct.
Direction 0 selects destination; 1 selects departure. Directions 2/10 are loops
even if circular metadata was missing. A loop may use an explicit subroute
destination, but never manufacture a destination from its final repeated stop.
Results include label provenance. Callers must provide last-stop metadata from
the same ordered route variant, not an unrelated route sharing a display name.

## Adapter boundary

See `tdx-api-contract.md` for verified schema documentation and research limits.
This layer is not a JSON decoder. Actual field mapping, station joins, subroute
endpoints, incomplete identities and source-time handling require validation at
the adapter boundary as source samples are verified. No UI, navigation, backend,
authenticated requests or hardcoded NIU stop selection are introduced.
