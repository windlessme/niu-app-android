# Discovery evidence

日期2026-09-29，僅為探索快照。JSON不含access token／client secret。

| 檔案 | 種類 | 來源 |
| --- | --- | --- |
| city-county-stops.raw.json | 工具保存的完整body，2972筆 | v2/Bus/Stop/City/YilanCounty?$format=JSON |
| city-stops.raw.json | 完整6筆內容，人工轉存／重新排版 | Stop/City/YilanCounty + contains(StopName/Zh_tw,'宜蘭大學') |
| city-stop-of-route.raw.json | 工具保存的完整body，15筆 | StopOfRoute/City/YilanCounty + Stops/any(s:contains(s/StopName/Zh_tw,'宜蘭大學')) |
| city-station.excerpt.json | 完整回應中取2個Station object | Station/City/YilanCounty + contains(StationName/Zh_tw,'宜蘭大學') |
| city-route.excerpt.json | Route ILA0771選取欄位＋771A子路線，非完整原始body | Route/City/YilanCounty + 五RouteUID OR條件（見discovery-report） |
| city-eta.excerpt.json | 完整回應中取2筆ETA object | EstimatedTimeOfArrival/City/YilanCounty + contains(StopName/Zh_tw,'宜蘭大學') |
| intercity-name-search.json | 查詢metadata包住實際回應 | 詳見檔案內URL |
| intercity-candidate-city-classification.json | 指定欄位實際route response | 詳見檔案內URL |

所有TDX資料以functions.webfetch觀察，工具未暴露upstream HTTP status/headers/cache provenance；同時本機直接HTTP與Code Mode fetch皆得到401。
因此raw是「工具輸出原body」，不代表已取得可獨立重現的授權原站response。
原始query採URL-encoded中文與$filter。範圍bbox另遇429，未反覆重試或繞過額度。

重要：不要把ETA樣本投入正式UI倒數，也不要把本目錄作正式allowlist；上線前需要授權重驗、完整分頁與範圍審查。
