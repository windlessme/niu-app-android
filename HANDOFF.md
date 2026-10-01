# HANDOFF

給接手的 Claude Code session。最後更新：2026-10-01。目前版本：**0.13.10+71**。

## 專案概況

- NIU-Life：國立宜蘭大學的非官方 Android 校園 App，用 Flutter 寫，原生部分用 Kotlin。功能、設計參考 iOS 版 [qian403/NIU-app](https://github.com/qian403/NIU-app)。
- 程式在 `mobile/`，applicationId 是 `me.windless.niulife`，minSdk 26，targetSdk 36。
- 沒有自己的後端：
  - 直接連學校系統（ccsys/ccsys1、acade、euni＝M 園區、sso）。
  - 從 GitHub raw 讀公開資料：`app-content/credits.json`（本 repo）、行事曆 `calendar-data/`（目前讀 **qian403/NIU-app**）。
- 架構說明：`docs/android-flutter-architecture.md`、`mobile/lib/core/platform/README.md`。

## 每次改完的固定流程（使用者要求，不用再問）

在 `mobile/` 底下執行：

1. `set -o pipefail; tool/verify.sh`，包含 calendar/toolchain/DOM 檢查、`dart format`、`flutter analyze`、`flutter test`，目前 316 項測試。
2. 把 `pubspec.yaml` 的 patch 版號和 build number 各加一。
3. commit 到 `main`，**push 到 origin main**。
4. `flutter build apk --debug`
5. `python3 tool/check_apk.py build/app/outputs/flutter-apk/app-debug.apk`
6. `python3 tool/publish_preview.py --apk build/app/outputs/flutter-apk/app-debug.apk --version X.Y.Z`
7. 給使用者下載連結：`http://<preview-server>:8080/NIU-Life-X.Y.Z-preview.apk`

## Release 簽章與 Play 上傳

- Upload key 在 repo 外面：`/root/.config/niulife-signing/upload-keystore.jks`，`key.properties` 也在同一個資料夾，密碼存在 `key.properties` 裡，權限是 600。可以用環境變數 `NIULIFE_KEY_PROPERTIES` 改路徑；找不到檔案時，release 會退回 debug 簽章。
- Upload key 的 SHA-256 指紋：`95:04:DD:13:D3:38:D6:E5:7C:83:89:42:9F:B0:A0:AB:25:4E:F1:1F:95:CE:AB:DC:5E:4B:B4:04:46:C8:4B:FA`。已經請使用者另外備份。
- 已啟用 Play 應用程式簽署：發布用的金鑰由 Google 保管，這把只是 upload key。
- 上傳流程：`flutter build appbundle --release`，然後用 MCP 依序 `edits_insert` → `bundles_upload` → `tracks_update`（internal，status `completed`）→ `edits_commit`。

其他慣例：

- 回覆一律用**繁體中文**。
- 查詢類畫面不要加「以學校為準」「資料來源」這類免責文字。
- commit 結尾要加 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`。
- 這台機器上的 auto-memory（`~/.claude/projects/-tmp-opencode-niu-app-android/memory/`）也記了這些規則，還有 Play 審查用示範帳號的說明。**示範帳號的密碼不要寫進 repo**，repo 裡只存它的 SHA-256。

## 這次 session 完成的事

| 版本 | Commit | 內容 |
|---|---|---|
| 0.13.4 | `b6bd403` | `NiuSection` 的標題和右側按鈕改成文字基線對齊，修好首頁「今天／完整課表」不在同一條線上 |
| 0.13.4 | `d5a1a8c` | 用商店截圖旗標 `NIU_STORE_SCREENSHOTS` 建置時隱藏系統列 |
| 0.13.5 | `e884a7d` | Google Play In-App Updates（彈性更新）。見 `lib/core/platform/play_update.dart` |
| 0.13.6 | `0f7e25a` | `NiuRow` 的值改成貼齊右側；版本號改用半形括號，顯示為 `0.13.6 (67)` |
| 0.13.7 | `1e3f05b` | 通知設定，功能和 iOS 版一致（見下節） |
| 0.13.8 | `2e2a3e1` | Release 簽章；第一個 AAB（versionCode 69）已上 Play internal 軌道 |
| 0.13.9 | `302587a` | 圖書館空間預約（見下節） |
| 0.13.10 | | 設備預約依 iOS 版重新設計（見下節） |

另外：

- google-play-developer MCP 已登記帳號 `niu-app`（金鑰在 `/root/.config/google-play-developer-mcp/service-account.json`），是目前使用中的帳號。
- MCP 工具已經可以直接用，服務帳號對 `me.windless.niulife` 有權限。

## 通知系統（0.13.7）

- 入口在「設定 → 通知 → 通知設定」，畫面在 `lib/features/notifications/notification_settings_screen.dart`。
- 排程邏輯在 `lib/features/notifications/campus_notifications.dart`，規則照 iOS 的 `Core/Models/AppState.swift` `NotificationScheduler`：

| 項目 | 規則 |
|---|---|
| 作業死線 | M 園區 14 天內到期的作業，截止前 24 小時通知，最多 20 項 |
| 重要日期 | 行事曆裡 `important`／`deadline` 類別、30 天內的日期，前一天台北時間 08:00 通知，最多 20 項 |
| 上課前提醒 | 每週上課前 10 分鐘。用原有的 `ScheduleReminders.kt`，提醒時間鏈式排程，一次只排下一堂 |

- 原生端 `CampusNotifications.kt` 負責單次通知：Flutter 每次把同一類的通知整批取代，排一個不精確的 AlarmManager 鬧鐘；送出時已遲到超過 6 小時的就丟掉。開機或 App 更新後會恢復排程；登出時，`ScheduleStore.clear` 會一起清掉。
- 什麼時候重新排程：App 啟動或還原 session、登入、課表快取更新時（`app.dart` 的 `_syncNotifications`）、切換開關、按「立即更新通知」。**沒有背景輪詢**，這點和 iOS 一樣。
- 上課提醒如果沒有手動設過學期日期，會用行事曆 `semesters` 欄位裡的 `classesStartDate` 到 `endDate`（`CalendarSnapshot.semesters`）。
- 上課提醒開關已經從課表選項移走；課表選項現在只剩「學期日期」和「匯出到行事曆」，並且會讀出裝置上已存的學期日期。
- 通知點下去的深層連結：新增 `niulife://moodle`、`niulife://calendar`，寫在 `lib/app/deep_links.dart`。
- iOS 的 Live Activities 和遠端即時動態沒做，Android 沒有對應功能。

## 圖書館設備預約（0.13.9 起，0.13.10 依 iOS 重新設計）

- 入口：「圖書館」頁底部 →「設備預約」，路由是 `/library/spaces`。程式在 `lib/features/library/`：
  - `webpac_client.dart`：API client。
  - `library_space_session.dart`：session 存取。
  - `space_models.dart`：模型、時段計算和篩選。
  - `space_booking_controller.dart`：狀態，對應 iOS 的 `LibraryEquipmentViewModel`。
  - `library_space_screen.dart`：畫面。
- UX 照 iOS 的 `Features/Library/LibraryEquipment*.swift`（qian403/NIU-app，2026-10-01）：
  - 兩個分頁：「預約設備」和「我的預約（數量）」。
  - 三個步驟卡片：選日期（14 天日期條，加「其他日期」）、選類別和設備、選開始時間（30 分鐘一格，分上午、下午、晚上）。
  - 底部固定的預約列：顯示摘要，用滑桿調整時長，按「核對預約」後重新查詢，開確認頁，然後送出。
  - 我的預約：可以搜尋，用日期範圍或設備篩選。
- 規則要用**所選設備的 equipId** 查 `getDayReservedByReader`。剩餘額度 = `maxCanReserveTotalUnit − inReserve`。
- 預約或取消送出後如果斷線、逾時或收到 5xx，會丟出 `SpaceUncertain`。這種情況不自動重送，要使用者重新整理「我的預約」並按「我已核對最新紀錄」後，才能再送出。
- 後端是凌網 HyLib WebPAC（`https://webpacx.niu.edu.tw`），走 GraphQL `/api/HyLibWS/graphql`。需要 `HYSESSION` cookie 和 `X-CSRF-Token`，token 從 `/equipment` 頁面的 `"csrfToken"` 取得。
- 登入：mutation `ssoLogin(user, pass, captcha: "", encrypt: true)`。帳號和密碼都用 AES-256-CBC 加密，金鑰寫死在網站前端，格式是 `ivHex:base64`。帳密和學校 SSO 共用。errorType 3 表示一個身分有多張證，要再呼叫 `ssoChooseLogin`。
  - **真實帳密的登入流程還沒實測過。** 加密有用 Python 算出的測試向量驗證。
- Session 存在 vault 的 `librarySession` 欄位，內容是 `{account, session}`。登入學校時會順便建立。舊使用者如果有「記住登入」就自動登入，沒有就在畫面上請他輸入一次密碼。
- 用到的 API：
  - `getEquipmentGroupInfo`：取群組，只顯示 `ebPolicy` 不是 null 的群組；「長期研究小間511」對學生沒有 policy。
  - `getEquipmentInfoList` 和 `getReserveEquipmentList`：取房間和已被預約的時段。
  - `getDayReservedByReader`：取規則，`equipId` 必須是真的房間 ID。
  - `reserveEquipmentCir`：預約，時間格式是 `YYYY/MM/DD HH:mm`，`muserid` 固定 100。
  - `getEquipmentByReader(status: Reserve|Borrow)`：我的預約和使用中。
  - `cancelEquipmentCir(eccId: equipmentCirContent.id)`：取消。
- 2026-10-01 用使用者的 session 實測過一次：預約 523討論室 10/02 10:00–11:00（預約編號 26762），之後已取消。
- 示範模式用 `DemoSpaceService`，資料存在記憶體裡。

## 重要決策

- **不架後端。** 需要遠端內容時沿用 credits 的做法：GitHub 上的靜態 JSON，加上 App 內建的離線版本和 revision 號碼。
- **In-App Updates 只用彈性更新。** 同一個 versionCode 只問一次；只有 release 版而且是從 Play 安裝的才會檢查，debug 預覽版、截圖版、側載版都跳過。下載完成後顯示 SnackBar「重新啟動」，透過 `MaterialApp.scaffoldMessengerKey`。
- **通知功能對齊 iOS，不多做。** 例如假日也不會略過上課提醒，提醒時間固定 10 分鐘。
- Play 主題圖片（1024×500）建議用 App 的淺色配色：漸層 `#F2F3F7` 到 `#E5EEFC`，標題 `#15171C`，強調色 `#0A62D0`。

## 尚未驗證／已知事項

- 通知、In-App Updates 都**沒在實機上測過**。In-App Updates 要用 Play 內部測試軌道，而且需要兩個不同的 versionCode 才測得出來。
- `NiuSection` 改成基線對齊、`NiuRow` 的值改成填滿空間，都會影響全 App。只用測試環境渲染確認過幾個畫面。
- 開關（Switch）在關閉狀態時看不到軌道外框，只剩灰色圓點。這是主題原本的樣式，還沒處理。
- 行事曆資料的網址指向 `qian403/NIU-app`，不是本 repo（`calendar_repository.dart` 的 `baseUrl`）。要不要改成自己維護，還沒決定。

## 可以接著做的事

1. 在實機上驗證三種通知和點通知後的跳轉，必要時調整文案或時間。
2. 等使用者把測試人員加進 internal 名單，再推版本號更大的 build，在實機上測 In-App Updates。
3. 用 release 版上 Play 內部測試軌道，驗證 In-App Updates。
4. 在實機上用真實帳密測試圖書館登入，包含登入學校時順便建立 session，以及在畫面上手動輸入密碼。
5. 遠端彈窗公告，使用者問過，還沒做：建議做法是 `app-content/announcements.json` 加 revision，同一個 revision 只跳一次。
6. 決定行事曆資料來源要不要改成本 repo。
7. 視需要調整 Switch 關閉時的樣式。
