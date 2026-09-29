# NIU Bus 最小代理與快取設計（Phase 1，尚未部署）

## 現有後端盤點

版本庫主要為 iOS＋Flutter，用戶端 README 明確寫活動推播／使用統計後端不在此庫。
未發現可擴充的 Node/Python/Go 業務伺服器或部署設定；`calendar-data/requirements.txt` 是離線資料驗證依賴。
本機 `/srv/niu-downloads` 的 Python HTTP server 只供 APK 靜態下載，不是校務或TDX代理。
因此不能假定已持有或可修改 niu-api.chien.dev 後端；本次只提供最小設計，不新增框架、不部署。

## 建議

獨立小型 HTTPS proxy，可沿用擁有者現有後端語言；若確定無後端，Python標準庫服務＋既有TLS反向代理即可原型，正式部署依團隊維運選擇。單實例先以記憶體快取＋SQLite保存最近成功快照；多實例才考慮共享快取，現在不導入Redis／大型framework。

### API contract（草案）

- `GET /api/bus/niu`：版本化站牌集合、服務清單與動態狀態摘要。
- `GET /api/bus/niu/stops`：allowlist內的站牌與上下車／方向關係。
- `GET /api/bus/niu/stops/{stopKey}/arrivals`：只接受allowlist識別碼，如`cityBus:ILA290880`（URL encode）。
- `GET /api/bus/routes/{routeKey}`：只接受經過allowlist的route，含各subroute站序，不能變成全台任意代理。

不得接收客戶端任意TDX URL／OData條件。參數由已驗證集合映射，停止訪客用戶端自行全宜蘭搜尋。

```json
{
  "schemaVersion": 1,
  "state": "stale",
  "scopeVersion": "reviewed-catalog-version",
  "fetchedAt": "2026-09-29T06:37:25Z",
  "sourceUpdatedAt": "2026-09-29T06:37:20Z",
  "expiresAt": "2026-09-29T06:37:55Z",
  "lastAttemptAt": "2026-09-29T06:38:25Z",
  "data": [],
  "error": {"code": "UPSTREAM_UNAVAILABLE", "retryAfterSeconds": 30}
}
```

以上是**合成契約範例**。data應帶上一次成功資料；`[]`僅用於那次成功結果確實為空。沒有快照時使用`data:null,state:error`，不能把401／429／逾時轉成空成功。
第一次載入中可HTTP202+state:loading+Retry-After；無快照上游失敗503；有舊快照200+state:stale。Flutter Repository也可用loading狀態承載舊資料。
各provider可能獨立失敗，因此每個來源／站牌維護狀態，不能用某一路正常就把全部標fresh。

## 認證

- TDX Client ID／Secret只在後端環境變數或部署secret store，不進Git、APK、dart-define、回應或日誌。
- 使用官方OAuth client_credentials token endpoint，依回傳expires_in快取，提前60秒且加jitter更新；同一時間只刷新一次。
- GET遇401可刷新Token重試一次；仍失敗回configuration/auth不可用。429依Retry-After／方案額度退避，不狂刷Token。
- 公開App查詢用代理自身限流／快取，不能把TDX Token交給Flutter。
- 靜態下載IP只有HTTP，不適合作正式TDX憑證代理；正式代理需HTTPS域名。

## NIU Bus Stops 集合策略

| 方案 | 優點 | 風險 |
| --- | --- | --- |
| A 後端版本化allowlist | 查詢少、範圍清楚、可審核變更 | UID可能更換，需定期核對 |
| B StationUID | 同站多路線易聚合 | 實際宜大有6個StationUID、3個group，不能只用1個Station；route side仍須StopOfRoute |
| C 固定bbox＋站名 | 可發現新UID與別名 | 地理鄰近不等於可安全步行到站；同名不等於同站，搜尋量較大 |

推薦 **A為服務端運行集合、B作關聯、C只作後端排程discovery校驗**。
本次發現UID寫入研究樣本而非Flutter operational constants。正式allowlist需帶source、StopUID、StationUID、座標、名稱、審查時間、來源VersionID、服務關係以及停用標記。
每天重新檢查名稱＋座標＋StopOfRoute，新增／移動／消失候選產生差異；保留上次有效版本，不能因上游失敗整批刪站。人工確認新候選後原子發布新scopeVersion。
路線集合由站牌站序反推，不hard-code歷史1786/751/753/771/771A。

## Cache與額度

- Static stop／station／route／subroute／sequence／operator：24h TTL，失敗可保留最近成功版本7天並明示stale；正式政策可調整。
- Dynamic ETA：初始建議30s共享cache，**可配置且依訂閱額度調整**，以6站OR條件單次聚合（確認OData支援後），不是每位使用者每站各打一次。
- 多請求single-flight；沒有活躍需求不持續輪詢；使用者手動更新仍受最短間隔限制。
- 30s整天輪詢約2880次／天／來源，不適合20次／日guest或低額度方案。上線前需確認TDX付費方案；若每分鐘更新，可依Quota改60s並顯示更新時間。
- freshness同時考慮local fetchedAt及source UpdateTime／SrcTransTime；HTTP新鮮不等於預估新鮮。DataTime在接近進站時可能長時間不變，不能單獨據此判定斷線。
- 初始產品政策：成功快照30s後可標stale、保留最多120s動態結果供提示；超過後保留最後成功資訊但停止顯示「進站中」或當作live倒數。靜態路線仍可用。
- 不對stale ETA持續倒數造成假精準，前景刷新由代理決定；後台不替每位使用者拉資料。
- 304保留既有body；解析異常與health299不能覆蓋正常快照。資料identity缺漏隔離，不捏造UID。

## Phase 1停止條件

本階段不新增BusPage、首頁入口、GPS、地圖、全宜蘭搜尋或後端執行服務。
正式接API前必須提供擁有者授權的TDX憑證／方案，從部署環境重驗401、200、429、快照時效與所有站牌路線join。
