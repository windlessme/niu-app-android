# NIU-Life Android 開發路線圖

- 日期：2026-09-28
- 配套設計：[Flutter 技術架構](android-flutter-architecture.md)
- 狀態：規劃初稿，Android 實作待啟動

## 1. 交付目標與估算前提

首版交付可安裝、可離線查看既有課表、可完成校務登入與主要校園操作的 Flutter Android App，並建立 Google Play 發行流程。

估算前提：一位熟悉 Flutter／Android 的開發者全職投入、有有效校務帳號與至少兩種 Android 真機、校方期間沒有重大改版。MVP 暫估 6～10 週開發與功能驗證；Play 帳戶驗證、適用的 14 天封閉測試與 Google 審查等待另計。P1 完成後重新估算。

## 2. P0：工具鏈與專案骨架

預估：1～2 個工作天。依賴：開發機可安裝工具鏈。

### 工作

1. 安裝並固定 Flutter stable、相容 JDK、Android SDK／build-tools／emulator；記錄版本與 `flutter doctor -v` 結果。
2. 建立 `mobile/` Flutter 專案、Android host、format／analyze 設定與 CI。
3. 加入最小依賴：Riverpod、go_router、Dio、WebView 與 secure storage；SQLite、掃碼於使用時加入。
4. 建立 configuration／composition root，讓正式、fixture 資料來源能由組裝入口注入。
5. 以暫定 applicationId 開始開發，列出正式發行者需確認的永久識別碼與 Play 帳戶資料。
6. 將 MIT License 與第三方套件授權放入可追蹤的發行資料。

### 驗收

- 開發機與 CI 都可建立並安裝 Android debug App。
- 有首頁、設定與校曆入口，路由與繁體中文顯示正常。
- 可從乾淨 checkout 重現依賴解算與建置，提交 lockfile。
- 記錄 API 26、targetSdk 36 與選用套件是否相容，若需提高最低版本則附裝置覆蓋取捨。

### 已知環境狀態

2026-09-28 本次規劃環境的 PATH 可找到 Node.js、Python 3；未找到 `flutter`、`dart`、`java`、`adb`、`sdkmanager`。此結果只代表目前 PATH，尚未完成 SDK 安裝位置盤點或 Android 開發環境設定。

## 3. P1：登入與校方介接技術驗證

預估：5～10 個工作天。依賴：P0、有測試帳號與可安排的點名測試情境。

這一階段交付可操作的 Android 原型與相容性紀錄，是後續功能全面開發的判斷依據。

### 切片 A：Modern SSO＋舊校務課表

- 建立可見的學校登入頁，處理使用者完成驗證碼與取消。
- 取得並驗證 SSO 身分、交換 GUID、在校務網站建立 Session。
- 導覽課表頁並抽出結構化資料，以簡單 Flutter 畫面呈現。
- 驗證 WebView／CookieManager／Dio 的必要互通與跨來源 frame 行為。

### 切片 B：Moodle API＋網頁點名

- 取得 Moodle API Token，成功讀取登入使用者的課程清單。
- 驗證 Moodle API 與 Moodle 網頁 Session 的獨立性；WebView 需要驗證碼時可手動完成。
- 掃碼、辨識有效點名路徑、顯示動作、進入校方頁面並解析結果。
- 對讀取失敗與有副作用操作失敗採不同重試策略。

### 切片 C：生命週期與清除

- 同時開啟多個功能只出現一次必要登入。
- 登入中切背景、返回、旋轉與 WebView 程序終止後有明確狀態。
- 登出時讓正在返回的 HTTP／WebView 請求失效。
- 清除被中斷後能在下次啟動完成，再開始新登入。

### 完成條件

| 驗證項目 | 通過標準 |
| --- | --- |
| SSO 正常／錯誤帳密／驗證碼／逾時 | 狀態正確，可取消、有人工完成路徑，不無限嘗試 |
| GUID 與課表 | 真機取得與官方顯示一致的課表；失效時能重新登入 |
| Moodle API | 課程資料屬於正確帳號；Moodle 失敗時其他功能可繼續 |
| 點名流程 | 可在安排好的測試情境中由使用者操作，未知回應不誤報成功、不重送 |
| 併發認證 | 同服務同時失效只觸發一次 refresh；舊 401 不清新 Token |
| 登出／換帳號 | 舊請求不能重新寫入；新帳號不顯示舊帳號資料或沿用 Cookie |
| 網路切換／離線 | 不將「有 Wi-Fi」當作登入成功，能呈現真實請求結果 |
| 真機相容性 | 至少兩種廠牌與不同 OS／WebView 組合，記錄 Android System WebView 版本 |

若 Flutter 套件缺少 Cookie／frame 能力，先以小型 Kotlin adapter 驗證補足。若整條登入流程仍有無法解決的真機阻礙，記錄可重現案例，再重新評估 WebView 邊界與平台方案。

## 4. P2：第一版核心功能

預估：P1 後約 4～7 週，依原型結果調整。

### 功能與完成定義

| 模組 | MVP 內容 | 完成定義 |
| --- | --- | --- |
| 登入／設定 | SSO、Moodle 分開狀態、記住登入選項、登出清除、政策／回報 | 重新啟動、離線、失效與換帳號測試通過 |
| 首頁 | 今日課程、點名與圖書館快捷、服務狀態 | 不同服務局部失敗不造成整頁不可用 |
| 個人課表 | 週課表、今日課程、更新時間、本機快照 | 離線能讀已同步資料，錯學期或舊資料有標示 |
| 學年度校曆 | 月／事件列表、搜尋、分類、來源 PDF、內建離線資料 | 現有日期／revision／hash 契約在 Dart 端通過 fixtures |
| M 園區 | 課程、公告、教材與作業資訊查閱、附件預覽 | Token 與附件權限正確，下載失敗可恢復、暫存可清除 |
| 點名 | 掃描、開啟校方流程、結果與紀錄入口 | 成功／拒絕／未知三種結果清楚，相機可正常暫停恢復 |
| 圖書館 | 門禁與借書圖碼 | 僅目前登入者可開啟，背景隱藏、返回重新取得 |

### 實作順序

1. 將 P1 原型收斂為 SessionCoordinator、WebSessionHost、Repository 與錯誤模型。
2. 完成個人課表持久化、離線狀態與帳號範圍清除。
3. 完成公開校曆契約與從 `calendar-data/` 產生內建 assets 的工具。
4. 接入 Moodle 查閱、圖書館與正式掃碼畫面。
5. 補齊附件預覽、設定、無障礙、深色模式與測試。

### 核心完成條件

- UI 能分辨沒有資料、離線快照、登入失效、校方服務失敗與網頁改版。
- 相機、Token、Cookie、圖碼與附件生命週期皆有可重現測試。
- 乾淨安裝可離線瀏覽內建校曆，校務個人功能登入後可用。
- 操作內文與官方回應一致，點名和作業資訊不因解析失敗產生虛假的成功／無紀錄。

## 5. P3：擴充與 Android 體驗

依使用頻率安排，每項獨立交付：

1. 歷年成績、GPA 與畢業門檻：先還原網頁解析並建立合成 fixtures。
2. 活動查詢、報名、修改／取消：獨立 Session 與有副作用操作狀態。
3. 作業檔案上傳與提交：系統選檔、上傳進度、失敗恢復、正式提交回應。
4. 課表 ICS 匯出：RRULE、學期截止、時區、避免意外重複匯入的介面說明。
5. 桌面課表 Widget、快捷入口與本機提醒：採版本化最小快照與平台測試。
6. OCR 登入輔助：以合法取得的測試影像建立辨識率基準，持續保留手動驗證。
7. FCM 遠端更新、活躍統計：取得自有後端契約後實作，更新資料流與隱私文件。

Flutter iOS 遷移以另一個里程碑安排，優先驗證同一套 Dart Repository 與 iOS WebView adapter，再評估 UI 與 Apple Extension 整合。

## 6. R1：Google Play 發行準備

可在 P2 期間同步準備，實際提交依驗收狀態。

| 項目 | 交付物 |
| --- | --- |
| 發布身份 | 已驗證的 Play Console 帳戶、永久 applicationId、聯絡資料 |
| 建置 | release AAB、版本碼、上傳金鑰管理、Play App Signing |
| 相容性 | target API 複查、arm64、最終 native libraries 的 16 KB 相容性與裝置測試 |
| 商店內容 | 圖示、截圖、功能描述、非官方定位、分級與目標對象 |
| 資料流 | Android 版公開隱私政策、Data safety、實際 SDK 與後端行為對照 |
| 審查存取 | 可持續登入的帳號、英文步驟、點名等功能的測試資源 |
| 測試軌道 | 內部測試、封閉測試、回饋與修正紀錄 |
| 正式發布 | 發行驗收、正式版權限與分階段發布設定 |

2023-11-13 後建立的個人開發者帳戶，依目前規定需至少 12 名測試者連續參與封閉測試 14 天，再申請正式版權限；其他帳戶依 Play Console 實際要求。測試人員加入與實際操作回饋一起規劃。

## 7. 優先測試清單

### 可重用現有行為的 fixtures

- `scripts/check-sso-login.js`：登入中、成功、密碼到期、錯誤及隱藏訊息。
- `scripts/check-attendance-login.js`：M 園區表單與驗證碼擷取／提交腳本。
- `scripts/check-grade-history.js`：不同展開行為的成績表格。
- `calendar-data/tests/test_calendar.py`：日期、跨年、週次、來源、revision 與雜湊。
- `docs/calendar-client.md`：台北午夜／8 月 1 日、CDN 不同步、延遲回應與完整快照替換。

### Android 需要新增的情境

- 實際 Chromium WebView 的 Cookie、HttpOnly、SameSite、iframe 與新視窗。
- 延遲請求跨越登出／新登入；WebView 清除未完成時不能開始換帳號。
- QR 重複偵測、相機權限拒絕、掃描途中來電／背景與返回。
- 系統回收程序後的 Session 重驗、清除恢復與 deep link。
- 私有資料備份／移轉排除、金鑰失效與重裝行為。
- 大字體、TalkBack、返回手勢、edge-to-edge 與平板版面。
- 正式 release 版與 16 KB page size 環境，而非只有 debug 模擬器。

## 8. 第一批可執行工作

| ID | 工作 | 依賴 | 交付物 |
| --- | --- | --- | --- |
| AND-001 | 工具鏈與 Android 專案初始化 | 開發環境 | `mobile/`、固定 SDK、可安裝 APK |
| AND-002 | 路由、Riverpod 與 fixture 組裝 | AND-001 | 可切換假資料的基本畫面 |
| AND-003 | Session 狀態與 CredentialVault | AND-002 | 具清除／失效測試的憑證邊界 |
| AND-004 | WebSessionHost 與 Modern SSO | AND-003、測試帳號 | 真機登入與互動驗證 |
| AND-005 | GUID／舊校務／課表解析 | AND-004 | 第一份真實課表 DTO |
| AND-006 | Moodle Token 與課程清單 | AND-003、測試帳號 | 獨立的 Moodle 登入與課程 |
| AND-007 | Moodle Web 登入與點名原型 | AND-004、AND-006、測試情境 | 有副作用操作與結果狀態驗證 |
| AND-008 | 併發、Cookie 清除與程序恢復 | AND-005、AND-007 | P1 驗證紀錄與選型定案 |
| AND-009 | 校曆 Dart 契約與 bundle 工具 | AND-002 | 可離線使用的校曆；可與登入切片同步開發 |

P1 紀錄至少包含裝置／OS／WebView 版本、套件版本、成功與失敗條件、待修問題及最終架構決策；不包含帳密、Token、有效 QR Code 或個人校務資料。
