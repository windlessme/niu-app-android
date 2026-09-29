# NIU Phase 1 — InterCity discovery

Observed 2026-09-29, approximately 06:35–06:38 UTC. Scope: TDX Basic v2 InterCity records with stop/station names containing `宜蘭大學`, plus classification of historical candidate route labels. This is not a claim about every bus within an unspecified campus radius.

## Result

The tool returned **zero InterCity stops, stations, or StopOfRoute records matching `宜蘭大學`**. It also returned zero InterCity routes for exact route labels 1786, 751, 753, 771, and 771A. No NIU-serving InterCity RouteUID was observed; none should be manufactured from a historical route number.

Current City/YilanCounty Route data positively identifies:

| Display label | Actual observed RouteUID | Classification |
| --- | --- | --- |
| 1786 | `ILA0786` | City/YilanCounty, BusRouteType 11 |
| 751 | `ILA0751` | City/YilanCounty, BusRouteType 11 |
| 753 | `ILA0753` | City/YilanCounty, BusRouteType 11 |
| 771 | `ILA0771` | City/YilanCounty, BusRouteType 11 |
| 771A | parent `ILA0771` | SubRouteUIDs `ILA0771A1` (direction 0), `ILA0771A2` (direction 1) in the full Route response |

The full City route query used the same exact-label OR filter as the InterCity query, with `/Route/City/YilanCounty` substituted. It returned four parent routes; 771A is nested under 771, not a separate parent RouteUID. The compact raw classification response is preserved in `samples/intercity-candidate-city-classification.json`. The parent discovery task owns City StopOfRoute linkage and campus-serving verification; City classification alone does not prove a stop is served.

## Actual queried endpoints and raw evidence

Base: `https://tdx.transportdata.tw/api/basic/v2/Bus`.

- `/Stop/InterCity?$filter=contains(StopName/Zh_tw,'宜蘭大學')&$format=JSON` → `[]`.
- `/Station/InterCity?$filter=contains(StationName/Zh_tw,'宜蘭大學')&$format=JSON` → `[]`.
- `/StopOfRoute/InterCity?$filter=Stops/any(s:contains(s/StopName/Zh_tw,'宜蘭大學'))&$format=JSON` → `[]`.
- `/Route/InterCity` with exact `RouteName/Zh_tw` OR matches for the five labels above → `[]`.
- `/StopOfRoute/InterCity/1786?$format=JSON` → `[]`.

Exact URLs and unmodified response arrays are archived inside metadata envelopes in `samples/intercity-name-search.json`. A nonempty control `/Route/InterCity?$top=1&$format=JSON` returned `THB0968`, RouteName `0968`, BusRouteType 13, UpdateTime `2026-09-29T09:58:11+08:00`, VersionID 7740. Thus these empty name results were not the only observed behavior of the tool.

### County enumeration and pagination

Queried `/Stop/InterCity?$filter=LocationCityCode%20eq%20'ILA'&$select=StopUID,StopName&$top=1000&$skip=0&$format=JSON`. The tool returned a full, untruncated array shorter than 1000 records, from `THB115497` (頭城站) through `THB311224` (南澳郵局), containing no `宜蘭大學`. A subsequent identical query with `$skip=1000` returned `[]` (archived). The requested 1000-record pagination is exhausted for that county-code filter; the first page is observed in the tool transcript, not archived as a full county sample in this document set. This does not cover missing or incorrectly assigned LocationCityCode values; the nationwide name query above independently avoids that county-code assumption.

An initial `City eq 'YilanCounty'` filter returned `[]`, but that is **not county evidence**: the actual InterCity Stop records use `LocationCityCode`, as verified by `/Stop/InterCity?$top=1&$format=JSON`. Do not reuse that erroneous filter. An exploratory bounding-box request (latitude 24.4–24.95, longitude 121.4–122) also returned data, but that rectangle was not a campus-distance definition and is not used to claim coverage.

## Official campus coordinate cross-check

Official NIU page: <https://www.niu.edu.tw/p/412-1000-1052.php> (交通位置), fetched as HTML on 2026-09-29.

- Explicit page text: `GPS衛星導航 北緯24.746111；東經121.749167`.
- Address: `260007 宜蘭縣宜蘭市神農路一段1號`.
- The embedded map URL separately contains longitude `121.74601899999999`, latitude `24.746178999999998`. These embedded map parameters differ from the explicit navigation coordinate and should not silently replace it or be asserted to identify a particular gate.
- For an initial official-source campus reference, use **lat 24.746111, lon 121.749167**, labelled “NIU official GPS navigation point”, not a surveyed campus centroid or bus-stop position.
- The official page places 751, 753, 771 (and 772) under `市區公車(小巴士)`. Its older route descriptions are historical hints, not current TDX identifiers. It says intercity/highway coaches reach 宜蘭轉運站, followed by local transportation or walking; it does not establish direct InterCity service at a stop named 宜蘭大學.

## Verification level and exact blocker

All successful JSON here is **tool-observed via functions.webfetch**, whose output did not expose HTTP headers, HTTP status, authentication, or cache provenance. It is not direct authenticated verification.

A direct unauthenticated curl to the encoded Stop/InterCity name query returned **HTTP/2 401**, response body **`Valid API Key Required`**, server Date **Tue, 29 Sep 2026 06:37:56 GMT**. No authenticated request was performed. Direct reproducibility is blocked pending authorized TDX authentication; the empty tool results must be rechecked through that path before treating them as production-verified absence.

Bounded conclusion: no name-matched NIU InterCity records were observed in these queries at this snapshot. Nearby stops with other names, station aliases, missing classifications, walking-distance requirements, and changes after the snapshot remain outside that conclusion.
