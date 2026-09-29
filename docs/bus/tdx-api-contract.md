# TDX bus API contract — NIU Phase 1

Research date: **2026-09-29**. Scope: official bus API research and backend-facing contract. “Documented” below means the official source describes it; “observed” means this research actually received that result. No authenticated data request was made. No current NIU stop IDs, route membership, or service availability are asserted here.

## Decision

Use **basic bus v2, `City/YilanCounty`** for NIU discovery and ETA integration. The current v2 OpenAPI explicitly includes YilanCounty. The ordinary v3 CityBus Stop, Station, Route, StopOfRoute, Schedule and EstimatedTimeOfArrival endpoints currently enumerate **only `Tainan`**. A v3 path must not be assumed to support YilanCounty merely because v2 does. These are documented coverage facts, not authenticated runtime verification. [S1][S2]

## Exact official sources

- **[S1] Current bus v2 OpenAPI JSON:** https://tdx.transportdata.tw/webapi/File/Swagger/V3/2998e851-81d0-40f5-b26d-77e2f5ac4118 — `info.version=v2`, `openapi=3.0.4`; endpoint parameters, response schemas and `components.schemas` are the primary contract. The `V3` in the document download URL is not the bus API version.
- **[S2] Current bus v3 OpenAPI JSON:** https://tdx.transportdata.tw/webapi/File/Swagger/V3/939d7b26-14d6-40bc-bdc9-a076e3f8d4dc — `info.version=v3`, `openapi=3.0.4`.
- **[S3] Official authentication/sample repository:** https://github.com/tdxmotc/SampleCode/blob/master/README.md — sections “API呼叫頻率限制”, “API認證機制”.
- **[S4] Official authentication guide:** https://motc-ptx.gitbook.io/tdx-xin-shou-zhi-yin/api-shi-yong-shuo-ming/api-shou-quan-yan-zheng-yu-shi-yong-fang-shi
- **[S5] Official bus dynamic-data caveats:** https://motc-ptx.gitbook.io/tdx-zi-liao-shi-yong-kui-hua-bao-dian/data_notice/public_transportation_data/bus_dynamic_data — especially common notes 1, 3, 5–9 and 12.
- **[S6] Official bus static-data caveats:** https://motc-ptx.gitbook.io/tdx-zi-liao-shi-yong-kui-hua-bao-dian/data_notice/public_transportation_data/bus_static_data
- **[S7] Subscription limits referenced by current documentation:** https://tdx.transportdata.tw/pricing — webfetch produced no readable page body during this research; exact plan-specific rates remain unverified.
- **[S8] Older FAQ (conflicting limits):** https://motc-ptx.gitbook.io/tdx-xin-shou-zhi-yin/api-shi-yong-shuo-ming/zi-liao-shi-yong-chang-jian-wen-ti

## Documented endpoints and schemas

Base URL: `https://tdx.transportdata.tw/api/basic`. All paths below are HTTP GET. [S1]

| Relative path | JSON success body / purpose |
| --- | --- |
| `/v2/Bus/Stop/City/YilanCounty` | `BusStop[]`: discover stop records, names, coordinates, bearing and station associations |
| `/v2/Bus/Station/City/YilanCounty` | `BusStation[]`: station grouping |
| `/v2/Bus/Route/City/YilanCounty` | `BusRoute[]`: route metadata, operators, origin/destination names and subroutes |
| `/v2/Bus/StopOfRoute/City/YilanCounty` | `BusStopOfRoute[]`: route/subroute/direction and ordered `Stops[]` |
| `/v2/Bus/Schedule/City/YilanCounty` | `BusSchedule[]`: `Timetables` and `Frequencys` (official spelling), either nullable |
| `/v2/Bus/EstimatedTimeOfArrival/City/YilanCounty` | `BusN1EstimateTime[]`: batch-updated N1 arrival estimates |
| `/v2/Bus/EstimatedTimeOfArrival/Streaming/City/YilanCounty` | Same N1 schema, individually updated source records; still a GET API, not a promise of browser SSE/WebSocket delivery |

Route, StopOfRoute, Schedule and both ETA forms also document a `/{RouteName}` variant. RouteName is the traditional-Chinese route name, not RouteUID; URL-encode it and verify returned identities rather than treating a human name as a unique key.

These endpoints expose `$select`, `$filter`, `$orderby`, `$top`, `$skip`, `health` and `$format`. `$format` is documented required (`JSON` or `XML`); `$top` has documented default 30. Choose explicit pagination and ordering rather than assuming an omitted `$top` guarantees a complete county snapshot. The observations below do not verify pagination semantics. `health=true` can produce **299** with a health schema, not ordinary bus records. V2 documents **304**, empty body, using `Last-Modified` / `If-Modified-Since`; retain the previous successful body on 304. [S1]

### Static identity contract

Schema names below have prefix `PTX.Service.DTO.Bus.Specification.V2.` in S1:

- `BusStop`: required `StopUID`, `StopID`, `AuthorityID`, `StopName`, `StopPosition`, `StationGroupID`, `UpdateTime`, `VersionID`. `StationID`, `Bearing`, `StopAddress` and city metadata are nullable. `StopName` is a multilingual name object (`Zh_tw`, `En`); coordinates are `StopPosition.PositionLat` / `PositionLon`. Bearing is geographic (`N`, `S`, `E`, `W`, `NE`, `NW`, `SE`, `SW`), distinct from route Direction.
- `BusRoute`: RouteUID/RouteID/RouteName, Operators, authority/provider metadata, update/version are required. `SubRoutes`, origin/destination names are nullable. The schema explicitly says `HasSubRoutes` does not have a strict relationship with the `SubRoutes` structure.
- `BusStopOfRoute`: required route and subroute identifiers/names, `Stops`, `UpdateTime`, `VersionID`; `Direction` is nullable. Join `Stops[].StopUID` to stop records and preserve `StopSequence`, subroute and direction context.
- `BusSchedule`: route/subroute identities, Direction and update/version required; `Timetables` and `Frequencys` nullable. Scheduled departures are not live arrivals. S6 warns some sources provide only important stops or the origin rather than a complete stop-by-stop timetable.

Backend recommendation: discover candidate names/coordinates, then validate route membership from StopOfRoute; preserve UID strings verbatim. Do not merge opposite-side stops by name or station group, infer IDs from a naming convention, or equate Direction 0/1 with north/south or “toward NIU.” Repeated stop occurrences may require StopSequence as well as stop/route/subroute identity.

### N1 v2 field definitions

Exact schema: `components.schemas["PTX.Service.DTO.Bus.Specification.V2.BusN1EstimateTime"]` in S1. Only **Direction and UpdateTime** are listed as required; most other fields, including identity fields, are nullable. Validation must account for missing or unusable data rather than manufacturing defaults.

| Field | Documented type / meaning |
| --- | --- |
| `StopUID`, `RouteUID`, `SubRouteUID` | Nullable strings; unique identifiers with authority prefix. Corresponding local IDs and multilingual names also exist. |
| `Direction` | Integer: **0 去程, 1 返程, 2 迴圈, 10 循環線, 255 未知**. Explicit warning: this is the vehicle's current route direction, **not necessarily the direction of the stop on its route**. |
| `StopStatus` | Nullable integer: **0 正常; 1 尚未發車; 2 交管不停靠; 3 末班車已過; 4 今日未營運**. |
| `EstimateTime` | Nullable integer, **seconds**. Schema: null for status 2–4 or `PlateNumb="-1"`; usually null for status 1, but some fixed-departure routes provide a value; normally populated for status 0. |
| `NextBusTime` | Nullable ISO8601 date-time string: **「下一班公車到達時間」**, e.g. format `yyyy-MM-ddTHH:mm:sszzz`. It is not a number of seconds or an origin-departure field. |
| `ScheduledTime` | Nullable string, **預排班表時間 HH:mm**; distinct from NextBusTime and live ETA. |
| `IsLastBus` | Nullable **boolean**, **「是否為末班車」**; not “last bus has already passed.” |
| `StopSequence` | Nullable integer, order of this stop on the route. |
| `StopCountDown` | Nullable integer, vehicle's number of stops from this stop. |
| `PlateNumb` | Nullable string; `"-1"` means no vehicle currently serving this stop according to the schema. S5 further explains it can mark a vehicle having passed the stop. |
| `Estimates` | Nullable array of `PTX.Service.DTO.Bus.Specification.V2.N1.Estimate`; do not assume every provider supplies it. |
| `DataTime` | Nullable date-time, time this estimate was calculated; schema says currently provided by the highway authority. |
| `SrcTransTime` | Nullable date-time, source platform transmission time. |
| `SrcUpdateTime` | Nullable date-time, source platform update time; source-dependent availability. |
| `UpdateTime` | Required date-time, **TDX platform update time**, not proof that a prediction was newly calculated. |

Important documented exception: both ETA endpoint descriptions explicitly state that **status 1 plus positive EstimateTime is normal in some cities, and the value is time until departure** (“預計多久後開始發車之時間”). Do not label that combination as an ordinary arrival countdown. [S1]

Recommended normalization (application policy, not additional TDX enums): retain raw fields and known statuses; treat null/missing/unknown status, invalid or negative ETA, and unusable identity as unknown/unavailable. Zero seconds is a valid numeric value, not missing. Status 2/3/4 must not be overridden by a contradictory numeric ETA. Preserve a valid NextBusTime as separately identified next-arrival information. Do not infer status 3 or 4 from an empty array, null ETA or IsLastBus=false.

### IsLastBus and timing caveats

S5 common note 6 says IsLastBus becomes 1 when the system detects the last bus actually running. If no vehicle movement/arrival/departure is detected, estimation may never trigger: **EstimateTime=null and IsLastBus=0 can occur even on a one-trip-per-day route**. The guide explicitly warns that IsLastBus alone misclassifies last-bus information. Its numeric 0/1 explanatory prose does not change the v2 schema's boolean type; actual Yilan N1 encoding was not observed here.

S5 also documents:

- Missing N1 can reflect vehicle equipment being off or querying outside operating time; it does not prove cancellation or no service today.
- Highway-authority/managed-county N1 does not necessarily provide first-stop next-bus times (common note 1). NIU cannot rely on NextBusTime always being populated.
- Batch N1 for the highway authority is sent approximately once a minute (notes 7 and 9), while other parts of the same guide discuss 30-second calculation updates and roughly 5-second source-fetch latency. These are different stages, not an end-to-end freshness SLA.
- Individually updated N1 needs an elapsed-time adjustment using `EstimateTime - (receipt time - SrcTransTime)` in seconds. S1's endpoint description misspells the field `SrcTrasTime`; the schema and S5 use **SrcTransTime**. Do not blindly apply this streaming rule to already-decremented batch data.
- Estimates can stop changing below 59 seconds until actual arrival. `SrcTransTime - DataTime` exceeding 90 seconds or even 30 minutes can be normal in that situation (note 8).
- TDX can retain the latest N1 for a route for **up to two hours** (note 12). A fresh HTTP response is not proof of fresh source data.

Backend recommendation: preserve source, platform and local fetched timestamps; explicitly mark stale data under a chosen application policy. Do not invent a TDX-guaranteed refresh interval or equate old DataTime alone with an outage.

## Why v3 is not a drop-in replacement

S2's ordinary CityBus v3 responses are **objects containing `Items[]`**, not v2 bare arrays. The N1 wrapper additionally requires `AuthorityCode`, `UpdateTime`, `UpdateInterval`, `SrcUpdateTime`, `SrcUpdateInterval`; `Count` is nullable. Static Stop's wrapper also requires VersionID.

Ordinary `PTX.Service.DTO.Bus.Specification.V3.N1Data` requires RouteID, StopID, Direction, RecTime and TransTime. Direction's description lists 0/1/2/255 (not v2's 10). IsLastBus is nullable boolean; StopStatus remains 0–4. **NextBusTime is absent from this ordinary v3 N1 schema.** Its EstimateTime field says null for status 1–4, although its endpoint prose retains the status-1/positive-ETA exception: this is a documentation inconsistency, not observed provider behavior.

The same v3 document also contains distinct **DRTS** and shuttle-bus schemas: some define IsLastBus as integer 0/1, add StopStatus 5, and define NextBusTime as **integer seconds**. These definitions must not be copied into ordinary v2 CityBus handling. None establishes ordinary v3 Yilan support. [S2]

## Authentication and limits

Documented M2M authentication is OIDC/OAuth2 **client credentials**. POST to:

`https://tdx.transportdata.tw/auth/realms/TDXConnect/protocol/openid-connect/token`

Use `Content-Type: application/x-www-form-urlencoded`, fields `grant_type=client_credentials`, `client_id`, `client_secret`; API GETs use `Authorization: Bearer <access_token>`. Token response includes `access_token`, `token_type=Bearer`, `expires_in` in seconds (documented default 86400). Cache according to the returned expiry; do not obtain a token on each bus request. [S3][S4]

- **Current S1/S2 introduction:** guest mode is browser-only, basic services only, **20 requests per source IP per day**. Exact evidence: “限以瀏覽器存取…限制每個呼叫來源端IP每日存取至多20次”.
- **Token endpoint:** S3 documents **20 calls per source IP per minute**, independent of data API limits.
- **Authenticated data API:** S3 says since **2024-04-29 12:00**, per-key limits depend on the subscribed plan; S1/S2 likewise point to S7. Do not hardcode a universal authenticated quota. Exact current plan rates could not be extracted from S7.
- S8's 50 guest calls/day and pre-subscription 50 calls/IP/second wording conflicts with newer S1/S2 and S3. Treat that FAQ as older guidance, not the current guest allowance or a guarantee of unlimited daily authenticated use.
- S4 documents 401 for missing/invalid authorization or missing scope/role; 429 for quota exhaustion; 416 for exceeding 60 parallel connections per IP; 423 for exceeding 50 parallel requests/second. These are documented gateway conditions, not limits tested in this session, and are not a replacement for plan-specific quotas.

Backend recommendation: server-side credentials/token cache, bounded refresh/retry, shared bus-response cache and plan-aware polling. On missing credentials or 401, report configuration/access unavailability rather than manufacturing successful empty bus data. No credentials were searched, guessed or supplied during this research.

## Observed access behavior: webfetch JSON versus direct 401

Both exact URLs were requested by **webfetch** and by local Python 3 `urllib.request.urlopen`, without an Authorization header supplied by this research:

1. https://tdx.transportdata.tw/api/basic/v2/Bus/Stop/City/YilanCounty?%24format=JSON
2. https://tdx.transportdata.tw/api/basic/v2/Bus/Stop/City/YilanCounty?%24top=1&%24format=JSON

| Client | Observation on 2026-09-29 |
| --- | --- |
| webfetch, URL 1 | Returned a large JSON body (saved by the research tool). This does not establish complete county coverage or authenticated backend access. |
| webfetch, URL 2 | Returned a one-record JSON array. Record UpdateTime was `2026-09-29T09:58:11+08:00`, VersionID `7740`. This is a static-stop timestamp, not live arrival data. |
| Local Python 3 urllib, URL 1 | At `2026-09-29T06:37:14.897886+00:00`, **HTTP 401**, body `Valid API Key Required`. |
| Local Python 3 urllib, URL 2 | At `2026-09-29T06:37:14.930941+00:00`, **HTTP 401**, body `Valid API Key Required`. |

Both direct responses exposed `Server: nginx`, `Date: Tue, 29 Sep 2026 06:37:14 GMT`, `Content-Type: application/octet-stream`. Neither had an Age, Via, X-Cache or WWW-Authenticate header in the inspected set. Webfetch did not expose raw status/headers or its transport/cache details, so its JSON cannot be classified confidently as fresh origin data versus an intermediary response.

**Conclusion:** the difference reproduces even with the same `$top=1` URL, so the evidence does not support blaming `$top`. It is compatible with documented browser-only guest access versus M2M authentication requirements. The precise mechanism (request classification, egress, intermediary caching, etc.) is **unverified**. No browser-header impersonation, quota probing or access workaround was attempted. Production integration must use the documented authenticated flow.

The parent's earlier report of `宜蘭大學` appearing in a webfetch Stop response is discovery evidence only. This research intentionally does not promote names or IDs from that response into a verified current NIU stop list. Verify selected stops, road side, route/subroute memberships, and actual N1 availability through authenticated requests before committing operational configuration.

## Remaining verification for implementation

1. With owner-supplied credentials, verify token acquisition and scoped Yilan Stop/StopOfRoute/ETA calls from the real backend runtime.
2. Record selected stop identities and source/version timestamps; verify both physical boarding locations and subroute/direction mappings.
3. Capture real N1 shapes and nullable-field behavior, especially NextBusTime, IsLastBus and status-1 ETA; do not use documentation examples as current service records.
4. Confirm subscription quota and choose cache, poll and stale thresholds accordingly. Authenticated 200/304, 429 and transient-error handling were not exercised here.
