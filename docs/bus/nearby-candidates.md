# NIU nearby stop candidates — saved-response geography check

Analysis date: 2026-09-29. No new network requests were made for this check.

## Evidence and method

- Original webfetch URL: https://tdx.transportdata.tw/api/basic/v2/Bus/Stop/City/YilanCounty?%24format=JSON
- Original saved tool output: `/root/.local/share/opencode/tool-output/tool_0ebe1278300114bESe827vOZmw`.
- Byte-for-byte repository copy: [`samples/city-county-stops.raw.json`](samples/city-county-stops.raw.json).
- Raw file: **1,334,628 bytes**; SHA-256 `7d352bba904c97407f93a34ea75dd6f54d1f6b2c86c02462bfb361906ff596b6`.
- Independently parsed the entire saved JSON array: **2,972 stop records**. This observed response **exceeds the documented `$top` default of 30**. It is a full copy of the received body, not proof that the county dataset is complete. No next-page metadata was available in this bare array, and pagination completion was not verified.
- Reference point: latitude **24.746111**, longitude **121.749167**, supplied by the requesting session as official NIU GPS. This check uses that supplied point; it does not independently verify its official provenance.
- Distance: haversine great-circle distance with Earth radius 6,371,000 metres; select records with numeric `StopPosition.PositionLat` / `PositionLon` and **unrounded distance ≤ 500 m**. Sort by distance and display rounded to 0.1 m. Distances are straight-line distances to the reference point, not walking routes, campus-boundary distances or entrance accessibility checks.

## Observed candidates within 500 m

**33 records**, including **6 named 宜蘭大學**. Preserve separate UIDs even where names or coordinates nearly coincide. All 33 records have `UpdateTime=2026-09-29T09:58:11+08:00` and `VersionID=7740` in the saved response. These are static discovery candidates; route membership, actual boarding side and current service remain unverified.

| StopUID | StopName.Zh_tw | Latitude | Longitude | Distance (m) | Bearing |
| --- | --- | --- | --- | ---: | --- |
| ILA290943 | 宜蘭大學 | 24.746056 | 121.749028 | 15.3 | NE |
| ILA292963 | 宜蘭大學 | 24.745951 | 121.748954 | 27.9 | NE |
| ILA290880 | 宜蘭大學 | 24.746037 | 121.748848 | 33.2 | S |
| ILA293042 | 宜蘭大學 | 24.7460523 | 121.7488422 | 33.4 | S |
| ILA234738 | 宜蘭大學 | 24.745793 | 121.7487815 | 52.6 | N |
| ILA234709 | 宜蘭大學 | 24.745743 | 121.74873 | 60.2 | SW |
| ILA303307 | 農權路 | 24.746678 | 121.750569 | 155.0 | W |
| ILA303306 | 農權路 | 24.746562 | 121.750682 | 161.0 | — |
| ILA302226 | 女中路二段 | 24.744943 | 121.751094 | 234.0 | E |
| ILA302229 | 女中路二段 | 24.744832 | 121.751111 | 242.4 | W |
| ILA305792 | 健康路二段 | 24.748135 | 121.751186 | 303.7 | SE |
| ILA305793 | 健康路二段 | 24.748467 | 121.751195 | 332.5 | NW |
| ILA234739 | 普門診所 | 24.748948 | 121.75029 | 335.2 | NE |
| ILA290936 | 普門診所 | 24.74899 | 121.75016 | 335.5 | SW |
| ILA303331 | 進士路 | 24.743416 | 121.747659 | 336.1 | S |
| ILA234708 | 普門診所 | 24.748996 | 121.750169 | 336.4 | S |
| ILA290951 | 普門診所 | 24.748972 | 121.750282 | 337.5 | N |
| ILA303330 | 進士路 | 24.74334 | 121.747754 | 339.6 | N |
| ILA296847 | 自強路 | 24.742838 | 121.750236 | 379.6 | — |
| ILA293055 | 蘭陽女中 | 24.7453995 | 121.7529549 | 390.6 | SE |
| ILA290906 | 蘭陽女中 | 24.745422 | 121.752972 | 391.8 | SE |
| ILA290889 | 蘭陽女中 | 24.745494 | 121.753019 | 395.0 | SW |
| ILA296848 | 自強路 | 24.742744 | 121.75045 | 396.2 | — |
| ILA293037 | 蘭陽女中 | 24.745555 | 121.753057 | 397.7 | SW |
| ILA296845 | 健康路一段 | 24.74433129 | 121.7526617 | 404.6 | S |
| ILA296846 | 健康路一段 | 24.744283 | 121.752709 | 411.4 | — |
| ILA292960 | 自強路口 | 24.742664 | 121.747448 | 420.8 | NE |
| ILA292937 | 自強路口 | 24.74263 | 121.74735 | 428.4 | SW |
| ILA290901 | 復興國中 | 24.749315 | 121.746617 | 439.6 | SE |
| ILA234710 | 自強路口 | 24.742521 | 121.7472 | 445.9 | S |
| ILA234737 | 自強路口 | 24.742455 | 121.747331 | 446.8 | NE |
| ILA290885 | 復興國中 | 24.74952 | 121.74648 | 466.2 | W |
| ILA293052 | 宜蘭自來水公司 | 24.748609 | 121.753284 | 500.0 | N |

`—` means no bearing value was obtained from the record. Bearing is not route Direction. Boundary candidate ILA293052 computes to **499.99913185931536 m** with this method and is included before rounding; its membership is sensitive to coordinate precision and distance model.

For documented schemas and the previously reproduced webfetch/direct-401 discrepancy, see [`tdx-api-contract.md`](tdx-api-contract.md). This saved response alone does not establish authenticated backend access or live ETA availability.
