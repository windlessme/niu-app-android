# NIU-Life Android／Flutter 技術架構

- 日期：2026-09-28
- 狀態：開發規劃初稿；套件與校方連線能力待 P1 真機驗證
- 分析基準：`96e8cdf3a4738ed31420f3de748fbee862906406`
- 執行順序與驗收：[Android 開發路線圖](android-flutter-roadmap.md)

## 1. 架構決策摘要

| 項目 | 決策 | 理由／驗證方式 |
| --- | --- | --- |
| 用戶端 | Flutter＋Dart，Android 優先交付 | 課表、校務資料呈現與 API 流程可共用，為後續 iOS 移植保留基礎 |
| 組織方式 | Feature-first，View／Controller／Repository／Adapter 分工 | 避免將網頁解析、登入與畫面合成大型檔案 |
| 狀態與依賴注入 | Riverpod，使用 Notifier／AsyncNotifier | 帳號範圍、生命週期與測試替身可明確管理 |
| 導覽 | go_router | 統一登入導流、分頁、通知與快捷入口 |
| 網路 | Dio，依服務建立具名用戶端 | SSO、Moodle、公開資料與可選開發者服務使用不同憑證策略 |
| WebView | 優先驗證 flutter_inappwebview | 此案需要 Cookie、JavaScript、跳轉、新視窗與框架操作；由 P1 決定是否需 Kotlin 補強 |
| 本機資料 | Drift／SQLite、secure storage、preferences 分工 | 結構化快取、憑證、一般偏好各有清楚生命週期 |
| 原生橋接 | Kotlin＋必要時使用 Pigeon | 小工具、系統整合與套件缺口使用具型別的平台介面 |
| 最低版本 | 暫定 Android 8.0／API 26 | 這是產品支援範圍提案；P0 依測試裝置、SDK 與套件最低版本確認 |
| 目標版本 | 初始 targetSdk 36，compileSdk 至少 36 | 依 2026-09-28 的一般手機 Google Play 規定；正式發行前複查 |
| 儲存庫 | 在本版本庫新增 `mobile/` Flutter 專案 | 校曆契約、文件、授權與跨平台 fixtures 可共同維護 |
| v1 服務拓樸 | 手機直接連校方服務；公共校曆讀取現有 JSON | 核心校務功能不需要建立帳密代理後端 |

此文件描述擬採用的設計，並不表示 Android 登入、掃描或建置已完成。套件版本在 P0 以當時相容的穩定版解算、鎖定並記錄；不使用浮動的 SDK 版本作為 CI 基準。

## 2. 現有實作對應

| 現有來源 | Android 可沿用的知識／契約 | Flutter 實作邊界 |
| --- | --- | --- |
| `Features/Authentication/Services/SSOLoginWebView.swift` | 新舊 SSO 導覽、登入結果、頁面腳本 | ModernSsoAdapter／LegacySsoAdapter |
| `Core/Services/SSOGUIDBridge.swift` | JWT 換一次性 GUID，再建立舊校務網站 Session | SsoApiClient＋AcademicPortalAdapter |
| `Core/Services/SSOSessionService.swift` | 同時登入合併、退避、前景驗證 | SessionCoordinator |
| `Features/Moodle/Services/MoodleService.swift` | Moodle Token、Web Service、附件與 HTML 備援 | MoodleApiClient＋各功能 Repository |
| `Features/Moodle/Views/MoodleWebView.swift` | 點名網頁登入、驗證碼與結果流程 | MoodlePortalAdapter＋AttendanceController |
| `Features/ClassSchedule/Services/ClassScheduleWebView.swift` | 課表頁導覽及表格擷取 | ScheduleRepository＋AcademicPortalAdapter |
| `NIU-LiveActivities/ClassScheduleModels.swift` | 課程、節次、台北時間與週次對應 | ScheduleSnapshot／ScheduleClock |
| `Features/Library/LibraryCodeService.swift` | 取得門禁圖碼與借書條碼的 HTTP 流程 | LibraryRepository |
| `calendar-data/`、`docs/calendar-client.md` | Schema、revision、hash、台北民用日期、離線規則 | AcademicCalendarRepository |
| `Core/Services/LiveActivityRemoteClient.swift` | 課程時段與資料刪除需求 | 後續通知服務契約；Apple attestation／推播流程需另行設計 |

Swift 邏輯需轉寫為 Dart 或 Kotlin；現有 JavaScript 可抽出為資產後沿用，但要去除 Swift 字串跳脫並通過 fixture 與 Android WebView 測試。

## 3. 系統分層與依賴方向

```text
Flutter Screens／Shared UI
           │ 使用者操作 ↓   ↑ 不可變畫面狀態
Riverpod Controllers／跨功能協調器
           │
Repository 抽象與實作（資料來源選擇、快取、領域規則）
           │
           ├── SSO／Moodle／Library HTTP Clients
           ├── 校務 Portal Adapters → WebSessionHost → Android WebView
           ├── Drift／Secure Storage／Preferences
           └── 平台介面 → 套件或 Pigeon → Kotlin／Android API

遠端資料來源：校方服務、GitHub Raw 公開校曆
後續選配來源：自有統計／FCM 推播服務
```

- View 只處理呈現、版面與互動，不能直接讀 Token、呼叫 Dio 或執行網頁腳本。
- Controller 將 Repository 結果轉為畫面狀態；複雜登入與跨功能清理由專用協調器負責。
- Repository 是功能資料的唯一入口；處理快取與 API／HTML 備援，避免畫面自行選資料來源。
- Adapter 封裝校方網站細節，回傳結構化 DTO，再映射為應用程式模型。
- Repository 抽象與平台介面在真正需要替身或多來源的邊界建立；簡單功能可以直接使用 Repository，無須為每次讀取再建立 UseCase。
- `app/` 是組裝入口，注入正式或 fixture 實作。`core/` 不反向依賴具體 feature；跨邊界需求使用小型介面注入。
- 公開資料 provider 可跨登入存在；個人功能 provider 由 `accountScopeId` 決定生命週期。

## 4. 建議目錄

```text
mobile/
  lib/
    main.dart
    app/
      bootstrap.dart
      app.dart
      router.dart
      providers.dart
      config.dart
    core/
      session/             # SessionCoordinator、狀態、epoch、認證介面
      network/             # Dio 用戶端、錯誤映射、重試與導向策略
      web/                 # WebSessionHost、PortalTask、URL／訊息驗證
      storage/             # DB、CredentialVault、備份與清除介面
      time/                # 校園日期、學年度與時鐘
      platform/            # Kotlin／套件的 Dart 包裝
      diagnostics/         # 不含個資的錯誤分類與本機診斷
    features/
      authentication/
      home/
      schedule/
      academic_calendar/
      moodle/
      attendance/
      library/
      grades/
      graduation/
      events/
      settings/
    shared/
      ui/                  # 卡片、空白／錯誤／離線狀態、載入元件
      theme/
    l10n/                  # 繁體中文 ARB、無障礙文字
  assets/
    portal_scripts/        # 隨版本發布的網頁腳本
    academic_calendar/     # 從現有 calendar-data 產生的內建快照
  pigeons/                 # 需要自有原生橋接時加入
  android/
  test/
    fixtures/
    session/
    repositories/
    calendar/
  integration_test/
  tool/
  pubspec.yaml
  pubspec.lock
```

每個 feature 按實際需要使用 `presentation/`、`application/`、`data/`、`models/`；只有複雜功能才再建立 `domain/`。先以單一 Flutter package 交付，出現第二個真正的消費端時再抽共用 package。

## 5. 套件與工具鏈

| 用途 | 預選 | 導入條件 |
| --- | --- | --- |
| 狀態與 DI | flutter_riverpod | account-scoped provider 與測試 override |
| 路由 | go_router | 登入、返回、冷啟動連結測試 |
| 網路 | dio | 請求取消、具名用戶端、逐跳導向與敏感日誌處理 |
| WebView | flutter_inappwebview | 通過 P1 的 Cookie、SSO、iframe、點名登入矩陣 |
| JSON | json_serializable | 對外 DTO 產生序列化；簡單領域模型可手寫 |
| SQLite | drift＋相容 SQLite backend | schema migration、原生相依套件與 16 KB page size 驗證 |
| 憑證 | flutter_secure_storage | 確認選定版本的 Android 加密實作、備份規則與失效處理 |
| 一般偏好 | shared_preferences | 主題、顯示偏好與清除進度等非憑證狀態 |
| 掃碼 | mobile_scanner | 真機相機生命週期、QR 去重與 native library 相容性 |
| 校園時間 | timezone＋intl | 資料使用 Asia/Taipei；顯示格式與民用日期分離 |
| 附件與分享 | path_provider／file_selector／share_plus，依功能導入 | 暫存清理、URI 授權與系統選檔測試 |
| 本機提醒 | flutter_local_notifications，於系統整合階段導入 | 通知拒絕、重開機與排程精確度設計 |
| 自有橋接 | pigeon | 只在套件缺口或 Widget 契約出現時加入 |

Flutter、Dart、JDK、AGP、Gradle、Kotlin 與 NDK 採相容組合，由固定 Flutter stable SDK 的模板起步。提交 lockfile 與 Gradle wrapper，CI 記錄工具版本。`dart-define` 適合非機密環境設定，內容可由 App 取出，不作為秘密儲存。

## 6. 多服務登入與帳號生命週期

### 6.1 狀態模型

App 級狀態：

```text
signedOut → signingIn → signedIn
                         ├── offlineCached
                         ├── interactionRequired
                         └── signingOut → signedOut
```

各服務另外保存 `unknown / authenticating / valid / expired / interactionRequired / unavailable`：

| 服務 | 認證方式 | 使用位置 |
| --- | --- | --- |
| Modern SSO | 學校登入頁、JWT | 身分資訊、GUID 交換 |
| Academic portal | 一次性 GUID 建立網站 Session Cookie | 課表、成績、畢業門檻 |
| Event portal | 活動系統自身登入流程與 Cookie | 活動查詢、報名 |
| Moodle API | `/login/token.php` 取得 Token | 課程、公告、教材、作業資料 |
| Moodle web | 網站 Cookie，可能需要互動驗證碼 | 點名與部分 HTML 備援 |

SSO 成功可進入個人功能。Moodle 失敗時將該功能顯示為待登入，不把整個 App 卡在登入畫面。`offlineCached` 只表示有上次個人快照，不代表伺服器認證仍有效。公開校曆可以未登入使用。

### 6.2 首次登入

1. Flutter 收集本次登入所需帳密，交由 AuthenticationRepository 使用；學校登入頁可見且可由使用者完成驗證。
2. ModernSsoAdapter 在確認網域與頁面後操作登入流程，取得 JWT，透過校方身分資訊回應確認登入身分。
3. 原始憑證只經指定校方 TLS 連線使用。Token 儲存至 CredentialVault；帳密預設僅留本次操作記憶體，使用者啟用「記住登入」時才加密保存。
4. Moodle API 認證有獨立逾時與結果，不阻塞 SSO 完成。學校網頁內手動輸入的密碼不靠額外攔截取得；必要時在 M 園區另行登入。
5. 請求課表時交換新的 GUID，在 WebView 建立 Academic Session，再導覽到課表頁。
6. 第一版以人工完成驗證碼確保可用；OCR 是後續便利功能，需要獨立辨識率與失敗退回驗證。

### 6.3 重新登入與併發

- 同一服務的重新登入使用 single-flight：十個失效請求只觸發一次認證，其餘等待同一結果。
- 需互動時，由 App 層呈現登入頁；背景工作回傳 `interactionRequired`，不在背景啟動 WebView 登入。
- 可重試的讀取操作最多在認證成功後重送一次；驗證碼失敗、帳密錯誤、429 與鎖定狀態使用限次與冷卻。
- 每次帳號切換或登出增加 `sessionEpoch`；所有請求、PortalTask、資料庫寫入與 Widget 更新都核對 epoch。
- Token 另有 generation：舊 Token 的延遲 401 不能清除較新的 Token。Moodle 的失效可能表現在 HTTP 200 的錯誤 JSON，也要由 Adapter 辨識。

### 6.4 登出與中斷恢復

`LogoutCoordinator` 依序執行：

1. 持久化「清除待完成」標記，增加 epoch，停止新個人請求與互動工作。
2. 取消 HTTP／PortalTask、停止相機、關閉 WebView，讓舊回呼失去寫入權。
3. 清除 CredentialVault、HTTP cookie 狀態、WebView Cookie、Web Storage 與相關網站資料；等待清除完成。
4. 清除個人 DB／WAL／暫存附件、圖碼記憶體、Widget 快照與個人通知。
5. 完成後清除標記，回到 signedOut。程序中斷時，下次啟動先完成清理，再允許登入或讀取個人資料。

帳號切換先走完整清除，避免預設共享 WebView Cookie 混用兩個帳號。公開校曆與非個人外觀偏好有獨立保存範圍。

## 7. WebView 與校方網站介接

### 7.1 WebSessionHost 與 PortalTask

`WebSessionHost` 統一擁有控制器、JavaScript bridge、Cookie 介面與生命週期。每個 PortalTask 具有目標服務、允許導覽範圍、taskId、sessionEpoch、逾時、取消與結構化結果。

- 以 Session 變更範圍為單位排隊；SSO bootstrap、驗證與登出不與依賴它們的導覽同時操作。
- 互動登入／點名使用可見 WebView。背景擷取可在前景期間使用專用 Host，但不能假設零尺寸或 headless WebView 在所有裝置都可靠。
- JS bridge 訊息核對來源頁、taskId、epoch 與 payload schema；頁面內容不能決定任意 App 方法、Token 讀取或外部網址。
- 校方跨來源 iframe 不假設能由頂層 JS 存取；P1 驗證套件的 frame 支援，必要時改為直接導覽實際內容頁或補原生 adapter。
- 頁面結構不符回傳 `PortalLayoutChanged`，保留舊快照並顯示重新整理／開啟官方頁入口。
- 腳本存於 `assets/portal_scripts/`，隨 App 發布並有 parserVersion。先以現有 Swift 內腳本與 fixtures 建立相同行為。

### 7.2 Cookie 與請求範圍

WebView CookieManager 與 Dio 並不自動共用。優先讓網站 Session 操作留在 WebView，Moodle Web Service 走 Token API；只有 HTML 下載等確有必要的路徑才透過 CookieBridge。

- 依特定目標 URL 向原生 CookieManager 取得 Cookie header，不嘗試由 `document.cookie` 讀取 HttpOnly。
- Android Cookie API 不一定提供完整 Cookie 中繼資料，因此不把一次讀出的 name/value 無差別複製到全域 cookie jar。
- HTTP 導向逐跳判斷目標；Cookie、Authorization、Moodle Token 只傳給明確允許的服務，換站時重新決定憑證。
- 需要回寫的 `Set-Cookie` 透過原生 Cookie API 處理；若套件無法保留必要的 domain/path/secure/expiry 行為，該流程留在 WebView 或補 Kotlin。
- URL 判斷使用解析後的 scheme、host、port、path；初始網站包含 `ccsys1.niu.edu.tw`、`ccsys.niu.edu.tw`、`acade.niu.edu.tw`、`euni.niu.edu.tw`、`sso.niu.edu.tw`，各服務使用自己的精確清單。
- Cookie、JWT、GUID、qrpass 與帶 Token 的附件 URL 不寫入日誌、路由、剪貼簿或分析事件。

## 8. 資料模型、快取與離線

### 8.1 儲存分工

| 資料 | 儲存方式 | 有效性／清理 |
| --- | --- | --- |
| JWT、Moodle Token、選配記住的帳密 | CredentialVault，包裝 secure storage | 按服務更新／失效，登出清除 |
| 網站登入 Session | 原生 WebView Cookie／Web Storage | 由網站驗證，登出與切換帳號清除 |
| 個人課表、課程摘要、後續成績等快照 | account-scoped Drift DB，App 私有目錄 | 登出清除；重新登入建立新的帳號範圍 |
| 學年度校曆 | 已驗證的完整 JSON 快照，獨立公開資料目錄 | revision/hash 更新；可供未登入及離線使用 |
| UI 偏好 | Preferences | 與個人資料分離 |
| 圖書館圖碼、點名 QR 內容 | 操作中的記憶體 | 離頁／背景／完成即清理，返回時重新取得 |
| 附件預覽 | 帳號範圍暫存檔 | 設容量與到期清理，登出清除；匯出副本由目的 App 管理 |

Drift／SQLite 預設不是加密資料庫；v1 的結構化快取以 Android App sandbox 保護並排除雲端備份／裝置移轉，憑證獨立加密。若產品需要應用程式層級的資料庫加密，另立決策驗證相容 backend、效能與 Widget 存取，不以「用了 Drift」宣稱已加密。

Secure storage 的密文、校務網站狀態與個人快取須覆蓋 Android 各支援版本的備份規則；金鑰失效時回到重新登入，不能將無法解密當作空密碼重試。

### 8.2 共用快照規則

個人快照包含 `accountScopeId`、`schemaVersion`、`source`、`fetchedAt`、`revision`（若來源提供）與 payload。每次完成寫入前核對帳號範圍、epoch 及該資源請求序號，避免晚回來的舊資料蓋過新快照。

- 先顯示上次有效快照，再在前景重新整理，介面顯示最後更新時間與離線狀態。
- 個人課表以帳號與可識別的學期分隔；若學期無法確認，標示來源與時間，不能自動推定最新學期。
- 連線狀態套件只能提供網路提示，不能判斷校方實際可達性；以請求結果決定錯誤。
- 自動重新整理採資源別間隔與同資源請求合併；手動重新整理可跳過一般間隔，但仍尊重校方限流。
- 課程可離線讀取；點名、報名與作業提交需即時連線，不能建立離線自動補送佇列。

### 8.3 日期與課程模型

- `CampusDate` 表達年月日，與 UTC timestamp 分開；校園「今天」固定採 Gregorian／Asia/Taipei。
- `ScheduleSnapshot` 保留課程、教師、教室、節次與曜日；由 `ScheduleClock` 產生具開始／結束時間的課程實例。
- 學年度於 8 月 1 日切換，不以已下載資料的最大年度決定。
- 公開校曆先驗證索引、路徑、schema、年度、revision、SHA-256 與日期規則，再原子替換整年度快照。
- `SHA-256` 用於索引與檔案一致性檢查，不當作來源數位簽章。
- hash 不符、CDN 不同步或不支援 schema 時保留同年度有效資料；完整替換可移除撤回事件。
- 事件起迄日皆包含當天；行事曆分類或寒暑假週次不直接用來取消個人課程。
- 校方確認沒有該年度、網路失敗、沒有本機快取，必須是不同 UI 狀態。

## 9. 點名與其他有副作用的操作

AttendanceController 使用明確狀態：

```text
idle → scanning → validatingCode → awaitingUserAction
     → openingPortal → authenticating（需要時）
     → processing → confirmed／rejected／unknown
```

- QR 掃描結果先驗證 HTTPS、精確學校網域與支援路徑；相機同一操作只接受一次結果。
- 開啟前提供動作資訊，注意某些點名 URL 僅載入就可能產生效果，因此「開頁」也視為可能有副作用。
- 使用者的操作觸發校方流程，成功必須有已辨識的校方結果；不能將 HTTP 200、載入結束或關閉頁面判定為成功。
- 不明回應保留為 `unknown`，顯示可讀說明與查詢點名紀錄入口；不得自動重送 QR URL。
- Dio retry interceptor、重新登入後重試、App 恢復與 deep link，都必須帶有讀取／副作用分類；點名、報名、取消報名、提交作業預設不自動重放。
- 出缺席紀錄沿用 API 優先、HTML 備援的資料來源策略。API 有效但只有 pending 狀態時，HTML 失敗仍可保留 API 結果，不能抹去有效資料。

## 10. Android 系統整合

### 10.1 功能介面

| 介面 | 初始實作 | 邊界 |
| --- | --- | --- |
| ScanGateway | mobile_scanner | 回傳 QR 值，相機暫停／恢復由平台包裝管理 |
| AttachmentGateway | Dart 下載＋系統預覽／分享 | 驗證下載目標；Token URL 不直接交外部 App |
| CalendarExportGateway | 產生 ICS、由使用者匯入 | 第一版匯出以系統選擇目的 App；完整處理 RRULE、時區與學期結束 |
| NotificationGateway | 本機通知套件 | 使用者啟用提醒時才取得相應通知權限 |
| WidgetSnapshotGateway | Pigeon＋Kotlin／Glance | 小工具讀最小化快照，避免把整個 SQLite／憑證暴露給原生顯示層 |
| AppShortcutGateway | Android App Shortcuts | 冷啟動導到掃描或圖碼入口，登入後再繼續 |

### 10.2 Widget 快照契約（第二階段）

快照至少包含 `schemaVersion`、`accountScopeId`、`sessionEpoch`、`generatedAt`、`validUntil` 與限定日期範圍的課程實例。以原子更新寫入 App 私有儲存；登出由原生清除入口同步刪除並重繪所有 Widget。

Kotlin 使用同一份 Golden fixtures 驗證台北日期與課程時間；快照過期顯示需更新，不以舊資料推算不存在的課程。Widget／通知 deep link 只帶資源 ID，不帶學號、憑證或點名秘密。

### 10.3 背景與推播

- WorkManager 用於可延後的快照更新與清理；執行時間由系統決定，不拿它保證課程開始瞬間更新。
- 一般提醒使用已取得的課表排程，處理通知被拒絕、重新開機、時區變更與登出取消。
- 若後續要求精準到分鐘，再獨立評估 AlarmManager 與 exact alarm 適用條件；拒絕權限時有明確降級。
- Android 通知以平台支援的形式呈現；Live Updates 是否符合使用情境需另驗證，不承諾複製動態島。
- 遠端推播在需要時增加 FCM backend。現有 Apple App Attest／APNs 流程無法直接由 Android 使用；需版本化註冊、撤銷、資料保存與刪除契約。
- 匿名活躍統計另有 UsageReporter 介面；啟用前確認自有後端的 Android 用量、UUID 生命週期、保存政策與 Data safety 宣告。

## 11. 錯誤、觀測與畫面契約

統一錯誤至少包含 `Offline`、`Timeout`、`CredentialsRejected`、`SessionExpired`、`InteractionRequired`、`RateLimited`、`ServiceUnavailable`、`PortalLayoutChanged`、`UnsupportedSchema`、`UnknownOperationResult`、`Cancelled`。

錯誤附服務名稱、階段、可否重試與不含敏感內容的 correlation ID。取消不顯示為校方故障。日誌記錄狀態碼與錯誤分類，不記錄密碼、Token、完整網頁、個人成績、圖碼或帶 query 的校務網址；使用者問題回報可預覽再寄出。

主要導覽暫定「首頁／課表／M 園區／校園／設定」；校園頁包含校曆、圖書館及後續服務。點名是可從首頁、M 園區與快捷入口到達的獨立流程。保留 TalkBack、大字體、深色模式、系統返回與平板自適應版面。

## 12. 測試與發行架構

- 單元／fixture：登入併發、Token generation、登出競態、快照覆寫、日期、HTML／JSON 解析、點名未知結果。
- Widget test：登入導流、離線快照、Moodle 局部失敗、錯誤恢復、字體放大與互動狀態。
- Android integration：實際 WebView、Cookie、iframe、程序回收、相機背景切換、附件分享與備份恢復。
- 校方端到端：使用測試者自己的有效帳號與安排好的測試資料；帳密由執行環境輸入，不能提交進版本庫。實際點名與報名由測試者主動操作，不納入 CI 自動提交。
- GitHub Actions 在 `mobile/` 相關變更執行 format、analyze、fixtures、Flutter test 與 Android build；定期或發行時執行模擬器／真機矩陣。
- 對 Flutter engine、SQLite、掃碼等最終 native libraries 驗證 64-bit 與 16 KB page size 相容性，檢查最終 APK／AAB 而非只看套件宣稱。
- 正式 release 產生簽署 AAB，採 Play App Signing；上傳金鑰由 CI secrets／發行環境提供。初次發行前確認永久 applicationId 的歸屬與可用性。
- 測試環境以 repository fixtures 與專用開發設定區隔。審查模式若加入正式 App，應明確標示示範資料並公開可用；不能以審查偵測來改變行為，且仍需提供可完整審查受限制功能的存取方式。

## 13. 已知未定項目

1. Android 最低版本暫定 API 26；依目標學生裝置與套件相容性定案。
2. 永久 applicationId、Play Console 發布帳戶與 App 名稱由實際發行者確認。
3. P1 驗證完成後決定 WebView 套件版本、是否需要 frame／Cookie 的 Kotlin 補強。
4. 首版「記住登入」採明示選項；是否要求預設自動登入，需與實測的校方驗證流程一起確認。
5. 審查帳號、課程與點名測試情境需要可持續使用的安排。
6. Flutter iOS 的實際遷移時程另列產品里程碑；共用程式碼的收益要在該平台採用後才實現。

## 14. 參考

- [Flutter 架構建議](https://docs.flutter.dev/app-architecture/recommendations)
- [Flutter 平台橋接與 Pigeon](https://docs.flutter.dev/platform-integration/platform-channels)
- [InAppWebView CookieManager](https://inappwebview.dev/docs/cookie-manager/)
- [Google Play 目標 API 規定](https://support.google.com/googleplay/android-developer/answer/11926878)
- [Android 16 KB page size](https://developer.android.com/guide/practices/page-sizes)
- [Google Play 審查登入資訊](https://support.google.com/googleplay/android-developer/answer/15748846)
- [Google Play Data safety](https://support.google.com/googleplay/android-developer/answer/10787469)
- [新個人帳戶測試規定](https://support.google.com/googleplay/android-developer/answer/14151465)
