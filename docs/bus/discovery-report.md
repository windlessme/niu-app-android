# 宜大公車 Phase 1：資料探索結論

日期：2026-09-29。範圍：明確命名「宜蘭大學」的站牌，以及校方GPS參考點附近候選。未建立UI、導航、地圖、GPS或正式後端。

## 證據層級（重要）

1. **已由目前 TDX API 網址回傳內容查得（webfetch工具觀察）**：Stop、Station、Route、StopOfRoute與ETA得到JSON，可互相join。靜態UpdateTime為`2026-09-29T09:58:11+08:00`／VersionID7740，ETA為14:37:20–25+08:00。
2. **尚未完成後端直接授權驗證**：同URL由本機urllib／fetch直接請求回401 `Valid API Key Required`；webfetch不提供原始HTTP headers／快取來源。因此不能宣稱這些內容已由我們的後端以授權token直接驗證，或已證明正式runtime可連線。
3. **範圍尚未定案**：以下6站為名稱精確符合宜大的候選核心集合；500m僅為交叉驗證範圍提案，不是正式周邊服務邊界。附近其他站與路線未完成逐一route join，不納入「全部路線」宣稱。

## 實際endpoint

Base `https://tdx.transportdata.tw/api/basic/v2/Bus`，查詢均帶`$format=JSON`。

| 資料 | endpoint與條件 |
| --- | --- |
| 核心站牌 | `/Stop/City/YilanCounty?$filter=contains(StopName/Zh_tw,'宜蘭大學')` |
| Station | `/Station/City/YilanCounty?$filter=contains(StationName/Zh_tw,'宜蘭大學')` |
| 經站服務 | `/StopOfRoute/City/YilanCounty?$filter=Stops/any(s:contains(s/StopName/Zh_tw,'宜蘭大學'))` |
| 路線詳情 | `/Route/City/YilanCounty?$filter=RouteUID eq 'ILA0751' or RouteUID eq 'ILA0753' or RouteUID eq 'ILA0771' or RouteUID eq 'ILA0772' or RouteUID eq 'ILA0786'` |
| ETA | `/EstimatedTimeOfArrival/City/YilanCounty?$filter=contains(StopName/Zh_tw,'宜蘭大學')` |
| 座標校驗 | `/Stop/City/YilanCounty?$format=JSON` 的已取得2972筆資料離線篩選，不由Flutter執行 |
| InterCity | `/Stop/InterCity`、`/Station/InterCity`、`/StopOfRoute/InterCity` 同名稱條件；county另用`LocationCityCode eq 'ILA'` |

範圍bbox請求曾回429，停止額外探索請求。正式服務以明確StopUID allowlist查ETA，名稱filter只用於discovery。`$top`預設30，正式discovery須指定分頁；本次命名Stop6筆、StopOfRoute15筆低於30，但仍不替未做的授權分頁驗證背書。

## 核心Stop集合：名稱均為「宜蘭大學」

座標順序為緯度、經度。StationUID取自Station API，不自行拼接StationID。
Direction來自各subroute的StopOfRoute，不是Stop本身欄位；N／S等Bearing另存。

| StopUID | StopID | StationUID | StationID | Lat, Lon | Bearing | 在此次站序中的Direction／服務 |
| --- | --- | --- | --- | --- | --- | --- |
| ILA234709 | 234709 | ILA111385 | 111385 | 24.745743, 121.748730 | SW | 0：1786 |
| ILA234738 | 234738 | ILA111384 | 111384 | 24.745793, 121.7487815 | N | 1：1786 |
| ILA290880 | 290880 | ILA129796 | 129796 | 24.746037, 121.748848 | S | 0：751、753 |
| ILA290943 | 290943 | ILA129819 | 129819 | 24.746056, 121.749028 | NE | 1：751、753 |
| ILA292963 | 292963 | ILA131229 | 131229 | 24.745951, 121.748954 | NE | 0：771、771A、772、772A |
| ILA293042 | 293042 | ILA131246 | 131246 | 24.7460523, 121.7488422 | S | 1：771、771A、771B、772、772A |

6個UID全部保留，不按中文名稱或接近座標合併。StationGroupID為`260－043`、`260－059`、`260－123`三組；不能僅靠單一StationUID代表宜大。

### 座標交叉驗證

[宜大官方交通位置](https://www.niu.edu.tw/p/412-1000-1052.php)明列GPS **24.746111, 121.749167**，地址神農路一段1號。上述6站距此點15.3–60.2m。
校方內嵌地圖有不同中心座標，不能當成同一個測量點。距離為直線距離，不推定步行路線或道路通行。

另在已取得的縣市Stop回應找到500m內共33筆候選，包含農權路、女中路二段、健康路二段、普門診所、進士路、自強路、蘭陽女中、健康路一段、自強路口、復興國中及邊界的宜蘭自來水公司。完整UID座標見 [nearby-candidates.md](nearby-candidates.md)。
這27個非同名近站尚未完成站序與可達性審查，**不把它們的未知路線列為已確認經宜大路線**。

## 路線與歷史對照

此次工具回應：**5個父RouteUID、8個顯示路線／支線、15筆方向服務**。屬City/YilanCounty（BusRouteType11）。

| 顯示路線 | RouteUID／RouteID | Operator | 0方向正式起→終 | 1方向正式起→終 | SubRouteUID | 結論 |
| --- | --- | --- | --- | --- | --- | --- |
| 1786 | ILA0786／0786 | 國光客運45 | 宜蘭轉運站→榮總員山分院 | 榮總員山分院→宜蘭轉運站 | ILA078601、ILA078602 | 存在且雙向停宜大；Headsign仍為宜蘭↔內城（經深溝） |
| 751 | ILA0751／0751 | 葛瑪蘭客運35 | 宜蘭轉運站→三興廟 | 三興廟→宜蘭轉運站 | ILA075101、ILA075102 | 存在且雙向停宜大；Headsign仍寫普門醫院 |
| 753 | ILA0753／0753 | 葛瑪蘭客運35 | 宜蘭轉運站→下埤 | 下埤→宜蘭轉運站 | ILA075301、ILA075302 | 存在且雙向停宜大；Headsign仍寫雙連埤 |
| 771 | ILA0771／0771 | 葛瑪蘭客運35 | 慈安路→金六結 | 金六結→慈安路 | ILA077101、ILA077102 | 存在且雙向停宜大 |
| 771A | 同父ILA0771 | 葛瑪蘭客運35 | 慈安路→金六結 | 金六結→慈安路 | ILA0771A1、ILA0771A2 | 仍是繞健康路一段支線，非獨立RouteUID |
| 771B | 同父ILA0771 | 葛瑪蘭客運35 | 未取得0方向 | 金六結→慈安路 | ILA0771B2 | 本次新增發現，繞宜蘭高中，只觀察到1方向 |
| 772 | ILA0772／0772 | 葛瑪蘭客運35 | 大坡→新福宮 | 新福宮→大坡 | ILA077201、ILA077202 | 舊清單未列，雙向停宜大 |
| 772A | 同父ILA0772 | 葛瑪蘭客運35 | 大坡→新福宮 | 新福宮→大坡 | ILA0772A1、ILA0772A2 | 舊清單未列，繞南津里，雙向停宜大 |

對應StopSequence：751=9/15，753=6/37，771=18/8，771A=21/8，771B=返程9，772=20/15，772A=20/18，1786=7/15。原始完整站序在samples/city-stop-of-route.raw.json。
「資料中存在並列入站序」不等於此刻有班次行駛；營運日與班次須Schedule／ETA另查。

### City／InterCity結論

不能從1786四位數推定為InterCity：它在此回應是City ILA0786。
InterCity的Stop、Station、StopOfRoute名稱查詢均空，候選歷史路線查詢也空；另用LocationCityCode=ILA分頁控制查詢沒有宜大同名站。詳見 [intercity-discovery.md](intercity-discovery.md)。
**工具資料中未觀察到直停「宜蘭大學」的InterCity服務**，但尚未直接授權驗證，也不代表500m所有別名站或所有未來路線不存在。

## ETA與方向

主用v2 batch ETA，保留SubRouteUID，不把771A／771B壓回771一筆。實際回應15筆，包含StopStatus0／1、EstimateTime可省略、PlateNumb為`-1`、IsLastBus為boolean，未出現NextBusTime（不能補造）。
`samples/city-eta.excerpt.json` 保存2筆實際回應：772 status1無EstimateTime；772A status0 EstimateTime1809、IsLastBus=true。只是查詢時間樣本，不能拿來顯示現在倒數。

| StopStatus | 官方意義 | domain／文字規則 |
| --- | --- | --- |
| 0 | 正常 | 秒數有效才按0–60進站中、61–119即將進站、>=120 ceil秒/60分；缺秒數但有未來NextBusTime可標scheduled |
| 1 | 尚未發車 | notDeparted；即使有秒數，也可能是距發車時間，不能標到站倒數 |
| 2 | 交管不停靠 | temporarilyNotStopping／交管不停靠，不泛稱路線停駛 |
| 3 | 末班車已過 | serviceEnded／末班車已過 |
| 4 | 今日未營運 | noService／今日未營運 |
| null／其他 | 未知 | unknown；保留NextBusTime原值，不因它推定未知狀態正常 |

Direction：0去程、1返程、2迴圈、10循環、255未知。不是方位，ETA中的Direction官方還提醒可能是車輛方向而非站牌方向；以route/subroute/stop/sequence匹配，衝突時保留異常，不猜。
方向文案優先使用相符SubRoute的DestinationStopNameZh；其次相符站序末站，迴圈特殊處理。父Route起終點只能在確認0/1對應時備援。資料不足顯示方向待確認。
例如751本次應顯示往三興廟／往宜蘭轉運站，另保留Headsign「普門醫院」來源文字，不能無條件覆蓋正式終點。

## 主要品質問題與待驗證

1. StationPosition與其StopPosition有小幅差異（如ILA131229 vs ILA292963），不能混用定位精度。
2. 同名同側有多個UID及多個StationGroup；不可按名稱／座標去重。
3. 771A、771B是SubRouteName，不是父RouteName；771B只觀察返程。
4. Headsign的普門醫院／雙連埤／內城與結構化終點三興廟／下埤／榮總員山分院不同；需顯示來源而非臆測哪個錯。
5. ETA的DestinationStop為本地StopID，部分不同於static當前末站ID（例如751 ETA308876 vs站序起訖）；不能靠該ID猜方向。
6. PlateNumb=-1、無EstimateTime、IsLastBus=false不能合成「進站中」或「無公車」。
7. 新下載HTTP回應也可能包含舊source資料；DataTime／SrcTransTime／UpdateTime分別保留。
8. webfetch與直接401的存取差異未解；需TDX授權與額度確認。
9. 500m附近27筆別名站未route join；首版allowlist建議先6個同名站，周邊範圍確認後才擴充。

完整schema與v2/v3理由：[tdx-api-contract.md](tdx-api-contract.md)。代理／allowlist／cache：[backend-cache-design.md](backend-cache-design.md)。domain：[domain-design.md](domain-design.md)。
