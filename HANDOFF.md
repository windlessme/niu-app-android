# HANDOFF

給接手的 Claude Code session。最後更新：2026-10-06。目前版本：**1.0.24+105**。

## 專案概況

- NIU-Life：國立宜蘭大學的非官方 Android 校園 App，用 Flutter 寫，原生部分用 Kotlin。使用者是 Android 版維護者；iOS 版由 Qian 維護（[qian403/NIU-app](https://github.com/qian403/NIU-app)），兩邊功能與設計保持一致。描述專案時不要說 Android 版「參考」iOS 版。
- 程式在 `mobile/`，applicationId 是 `me.windless.niulife`，minSdk 26，targetSdk 36。
- 沒有自己的後端：
  - 直接連學校系統（ccsys/ccsys1、acade、euni＝M 園區、sso）。
  - 從 GitHub raw 讀公開資料：`app-content/credits.json`（本 repo）、行事曆 `calendar-data/`（目前讀 **qian403/NIU-app**）。
- 架構說明：`docs/android-flutter-architecture.md`、`mobile/lib/core/platform/README.md`。

## 每次改完的固定流程（使用者要求，不用再問）

在 `mobile/` 底下執行：

1. `set -o pipefail; tool/verify.sh`，包含 calendar/toolchain/分層/DOM 檢查、`dart format`、`flutter analyze`、`flutter test`，目前 383 項測試。
2. 把 `pubspec.yaml` 的 patch 版號和 build number 各加一。
3. commit 到 `main`，**push 到 origin main**。
4. `flutter build appbundle --release`，上傳到 Play internal 軌道（步驟見下節）。**每個新版本都要推。**

**不要在本地建 debug APK**（使用者 2026-10-06 決定）：不跑 `flutter build apk --debug`、`check_apk.py`、`smoke_android.py`、`publish_preview.py`，也不給預覽下載連結。工具還留在 `tool/`，使用者要求時才用。預覽 APK 的下載服務（systemd `niu-downloads`、`niu-downloads-router`）2026-10-07 已停用並取消開機啟動，`publish_preview.py` 要先重新啟用服務才有用；不要把主機位址寫進 repo。

## Release 簽章與 Play 上傳

- Upload key 在 repo 外面：`/root/.config/niulife-signing/upload-keystore.jks`，`key.properties` 也在同一個資料夾，密碼存在 `key.properties` 裡，權限是 600。可以用環境變數 `NIULIFE_KEY_PROPERTIES` 改路徑；找不到檔案時，release 會退回 debug 簽章。
- Firebase 設定檔（`google-services.json`，專案 `niu-life-ac16e`）也放在 repo 外：`/root/.config/niulife-firebase/google-services.json`，可以用 `NIULIFE_GOOGLE_SERVICES` 改路徑。建置時 Gradle 會把它複製到 `android/app/`（已加進 gitignore）並套用 Google Services 外掛；找不到檔案時照常建置，但 Analytics 會停用。
- Upload key 的 SHA-256 指紋：`95:04:DD:13:D3:38:D6:E5:7C:83:89:42:9F:B0:A0:AB:25:4E:F1:1F:95:CE:AB:DC:5E:4B:B4:04:46:C8:4B:FA`。已經請使用者另外備份。
- 已啟用 Play 應用程式簽署：發布用的金鑰由 Google 保管，這把只是 upload key。
- Play 各軌道現況（2026-10-03 用 MCP 查過）：
  - **正式版：1.0.0 (81)**，已審核通過並發布。**1.0.17 (98) 已送審**（使用者 2026-10-06 告知）。
  - 公開測試（beta）：1.0.0 (81)。
  - internal：**1.0.24 (105)**（2026-10-06 推送）。
- 正式版由使用者在 Play Console 升級（Claude 推 production 會被權限擋下，屬正常）。
- **正式版不用每版都推**，只要 versionCode 比上一個正式版大就行。建議 internal 每版都推；等使用者在手機上測過、累積一批改動或有重要修正時，再挑一版推正式版。**版本說明的寫法（使用者 2026-10-05 要求）**：
  - internal：只寫**這一版**改了什麼，讓使用者知道要測哪裡。沒有使用者看得到的改動時寫「內部調整，功能沒有變化」。不要再沿用累計說明，否則每版看起來都一樣。
  - 正式版：寫「從上一個正式版到現在的所有改變」。推正式版時由使用者貼上，草稿維護在下面的「下一個正式版的說明草稿」，每次 internal 有使用者看得到的改動就一起更新。
- 1.0.17（含 1.0.4、1.0.5、1.0.8～1.0.17 的改動）已送審為正式版。審核結束前不要再提交新的正式版，否則會重新審查。下一個正式版的說明草稿從 1.0.17 之後重新累計。
- **1.0.17 正式版的版本說明**（1.0.0 之後的累計改動，已送審）：
  ```
  ・長按 App 圖示可以直接開啟點名、課表、M 園區與圖書館入館碼
  ・新增桌面小工具：快捷列、下一堂課；今日課表加上快速點名與入館碼按鈕
  ・新增「上課中通知」：顯示課名、教室、下課倒數與下一堂課（在通知設定開啟）
  ・上課前提醒更準時
  ・請假：統計只列出有請假的假別，明細自動讀取簽核流程，顯示簽核人與退回原因
  ・請假節次改成依日期分組，列出課名與老師，連續節次合併顯示
  ・郵件包裹打開就自動查詢自己的郵件
  ・首頁今日課表：還沒開始的第二堂課改標「稍後」
  ・點 niu-life.app 的下載或功能連結，已安裝時直接開 App
  ・課表可以切換「整週」，一次看完一週的課，標出今天與現在時間
  ・新增公告：重要消息會顯示在首頁，也可以在「設定 → 公告」查看
  ・開關關閉時更容易看出狀態，整列都能點擊切換
  ・隱私權說明加上完整政策的連結，聯絡信箱改為 hi@niu-life.app
  ・效能最佳化，較舊的 Android 版本也支援無邊框畫面
  ```
- **下一個正式版的說明草稿**（1.0.17 之後的累計改動）：
  ```
  ・修好教材與信件附件無法分享或儲存
  ・.html 等網頁格式的教材可以下載
  ・教材下載後可以直接用手機上的 App 開啟
  ・M 園區新增「即將截止」，列出還沒交的作業
  ・分組名單、公告等頁面直接在 App 內顯示
  ・首頁可以隱藏姓名，只顯示「○同學」
  ・行事曆不用切換月份，往下就能看到之後各月的事項
  ・作業死線與重要日期通知更準時
  ・歷年成績加上 GPA 走勢圖、學期篩選與通過率，各學期可以收合，班級排名直接顯示在學期上
  ・期中、學期成績顯示班級排名與課程數，每門課標出必修、選修等類別
  ```
- 公開測試的使用者會自動拿到 versionCode 較大的正式版，公開測試軌道不用特別處理。release 名稱用 `X.Y.Z (versionCode)`，附一句 zh-TW 版本說明。
- 上傳流程（每個新版本都要做）：`flutter build appbundle --release`，然後用 MCP 依序 `edits_insert` → `bundles_upload` → `tracks_update`（internal，status `completed`）→ `edits_commit`。

其他慣例：

- 回覆一律用**繁體中文**。
- **對外窗口一律一致（使用者 2026-10-05 決定）**：
  - 聯絡信箱：**hi@niu-life.app**（iOS 版與 Android 版共用，Cloudflare Email Routing）。不要再用 hi@windless.me。
  - 隱私權政策：**https://niu-life.app/privacy**，iOS 版、Android 版與網站共用一份，唯一來源是 niu-life-site 的 `src/content/privacy.md`。本 repo 不再有政策檔。App 內「設定 → 隱私權」是摘要（`privacy_screen.dart`），政策有實質變動時一起改，底部有「完整隱私權政策」按鈕連到網站。
  - 網站：https://niu-life.app/，下載連結 https://niu-life.app/download。
  - 問題回報表單：https://forms.gle/2ok6fydShrfe6PHr5。
  - 開源專案連結指向本 repo；本 repo 的 GitHub 首頁欄位是 https://niu-life.app。
- 查詢類畫面不要加「以學校為準」「資料來源」這類免責文字。
- commit 結尾要加 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`。
- 這台機器上的 auto-memory（`~/.claude/projects/-tmp-opencode-niu-app-android/memory/`）也記了這些規則，還有 Play 審查用示範帳號的說明。**示範帳號的密碼不要寫進 repo**，repo 裡只存它的 SHA-256。

## 這次 session 完成的事

| 版本 | Commit | 內容 |
|---|---|---|
| 0.13.4 | `c76f604` | `NiuSection` 的標題和右側按鈕改成文字基線對齊，修好首頁「今天／完整課表」不在同一條線上 |
| 0.13.4 | `e7c7919` | 用商店截圖旗標 `NIU_STORE_SCREENSHOTS` 建置時隱藏系統列 |
| 0.13.5 | `7a65f0a` | Google Play In-App Updates（彈性更新）。見 `lib/core/platform/play_update.dart` |
| 0.13.6 | `eda8ac9` | `NiuRow` 的值改成貼齊右側；版本號改用半形括號，顯示為 `0.13.6 (67)` |
| 0.13.7 | `802168d` | 通知設定，功能和 iOS 版一致（見下節） |
| 0.13.8 | `a368a33` | Release 簽章；第一個 AAB（versionCode 69）已上 Play internal 軌道 |
| 0.13.9 | `765c663` | 圖書館空間預約（見下節） |
| 0.13.10 | `e430de7` | 設備預約依 iOS 版重新設計（見下節） |
| 0.13.11 | `da1c6e8` | 校園信箱（全原生，見下節） |
| 0.13.12 | `d5f3b19` | 修好讀信顯示、刪除和移動誤報失敗；右上角改成 App 內的學校信箱網頁 |
| 0.13.13 | `fdc7d78` | 寬版信件縮到螢幕寬度，加「原始大小」全螢幕檢視；信件列表改成分頁 |
| 0.13.14 | `94d5972` | 修好信件圖片在窄螢幕上變形 |
| 0.13.15 | `13e71ca` | 首頁／課表／M 園區可左右滑切換並保留狀態，返回鍵先回首頁；課程詳情分頁可左右滑 |
| 0.13.16 | `2f1e833` | 修好成績三個分頁都卡在「請在學校網頁完成驗證」；期中／學期成績改讀結果頁 |
| 0.13.17 | `9528040` | 成績、在學證明加快取（`33a169a`）；課表、M 園區的標題和按鈕放同一列，拿掉上方留白 |
| 0.13.18 | `93af820` | 所有頁首統一成單列；請假頁只留一個重新整理（加下拉更新）；修好示範模式成績顯示「尚未更新」 |
| 0.13.19 | `de582c3` | 加入 Google Analytics（Firebase）與設定開關；更新隱私權政策；開源專案連結改為本 repo；聯絡信箱改為 hi@windless.me |
| 1.0.0 | `b3395f4` | 第一個正式版，內容同 0.13.19 |
| 1.0.1 | `bd0bc0a` | App 捷徑改為點名／課表／M 園區／入館碼並換圖示；新增「快捷列」小工具；上課中通知；上課提醒改為逐步逼近的鬧鐘；刪除公車殘留 |
| 1.0.2 | `138fdb7` | 修好快速點名冷啟動停在 M 園區；課表小工具改為總是讀得到課表；新增「下一堂課」小工具，「今日課表」加上快速點名與入館碼按鈕；請假確認提示改文字 |
| 1.0.3 | `041334e` | 通知設定的開關整列都可以點 |
| 1.0.4 | `306e4d2`、`38eb4b4` | 升級 AGP 9.1.1／Gradle 9.3.1／Kotlin 2.4.0，啟用最佳化資源縮減；舊版 Android 也採用無邊框畫面 |
| 1.0.5 | `c02ddcc` | 郵件包裹打開時自動用登入姓名查詢自己的郵件，和 iOS 一樣 |
| 1.0.6 | `7cac283`–`ed9aa25` | 整理程式架構，使用者看不到差異（見「程式架構整理」） |
| 1.0.7 | `4819cc2` | 拆開超過 1000 行的畫面檔，使用者看不到差異 |
| 1.0.8 | `c1bd4d4` | 開關關閉時改成灰底加外框，看得出是關著的開關（淺色、深色都是） |
| 1.0.9 | `5c054c0` | 請假統計：假別名稱去掉括號、0 節合併成一行、卡片等高且每列填滿；明細自動讀取簽核流程，顯示簽核人、意見與退回原因 |
| 1.0.10 | `ebe1a97` | 首頁今日課表：兩堂都還沒開始時，第一堂標「下一堂」、第二堂標「稍後」（以前兩堂都是「下一堂」；iOS 也有同樣問題） |
| 1.0.11 | `f52f690` | 請假節次統一顯示：依日期分組，同一堂課連續節次合併成「第 3–4 節」並列出課名與老師；用在申請表、送出確認、請假明細，紀錄列表顯示「10/8（四）・第 3–4 節・共 2 節」；節次選擇分開讀教師／課名／教室 |
| 1.0.12 | `7908e52` | 課表加「單日／整週」切換，整週為格狀表；遠端公告（首頁卡片、一次性彈窗、設定 → 公告） |
| 1.0.13 | `d099bd6` | 設定的「版本」移到「關於」最下面（開源授權下方） |
| 1.0.14 | `454fd43` | 整週課表重新設計：填滿畫面高度、星期下加日期、今天欄位底色、現在時間紅線、課程格左側色條與較深底色；週六日有課時也不用左右滑 |
| 1.0.15 | `d8b0577` | 隱私權說明（App 內與 `docs/android-privacy-policy.md`，更新日期 2026-10-05）加上公告：從 GitHub 讀取、只在手機記住關掉的公告編號 |
| 1.0.16 | `0f6e58a` | App Links：`https://niu-life.app/download` 開 App、`/open/<功能>` 開對應功能（manifest `autoVerify` + `campusDeepLink`） |
| 1.0.17 | `49931e0` | 隱私權畫面：聯絡信箱改 hi@niu-life.app、加「完整隱私權政策」按鈕連到 niu-life.app/privacy（兩平台共用政策）；刪除本 repo 的 Android 專用政策檔 |
| 1.0.18 | `c90789d` | M 園區網頁自動登入改寫（1.0.19 已還原，見「M 園區網頁登入」）；修好教材／信件附件分享（暫存資料夾建立失敗）；.html／.json 教材可下載；作業與重要日期通知改用 `wakeBy` 逐步逼近 |
| 1.0.19 | `fa790b5` | 還原 1.0.18 的 M 園區網頁登入架構（使用者回報課程讀取變慢）；保留附件分享、.html 下載、通知時間的修正 |
| 1.0.20 | `f019eef` | M 園區教材下載後加「開啟」按鈕，用手機上的 App 開啟（使用者選擇不做 App 內預覽）：檔案寫在 `cache/attachments/`，原生 `DownloadedFiles.kt` 經 `niulife/files` 以 FileProvider 開 ACTION_VIEW，沒有對應 App 時提示改用分享 |
| 1.0.21 | `630194e` | 依 iOS（qian403/niu-app `Features/Moodle/Upcoming`、`CourseDetail/MoodleCourseResourcesView.swift`）：M 園區頁面上方加可收合的「即將截止」（目前學期、逾期 7 天到未來 14 天、只列未繳交，`moodle_upcoming*.dart`）；教材依類型開啟（`moodle_module_open.dart`）：頁面讀 `mod_page_get_pages_by_courses` 在 App 內顯示 HTML、討論區直接列討論、作業直接開作業、單一檔案直接下載、.html 檔在 App 內顯示 |
| 1.0.22 | `bc66f5d` | 依 iOS `HomeView.swift`：首頁問候語旁的眼睛按鈕隱藏姓名，顯示「姓＋同學」（含複姓），切換時亂碼動畫、尊重減少動態效果，設定存在 `home.isNameMasked`；`main()` 先讀，讀到前一律遮蔽（`features/home/name_mask.dart`）。行事曆月曆模式在當天事項下方加「接下來」，依月份列出選定日期之後到學年結束的事項（使用者需求，iOS 沒有）。修好 M 園區頁面在深色模式文字變黑（CSS `*{color:inherit}` 連 body 也繼承成預設黑色） |
| 1.0.23 | `c9e6053` | 依 iOS `Features/GradeHistory/`（`GradeHistoryView.swift`）補齊成績：歷年加 GPA 走勢圖（兩學期以上）、學期篩選 chip（篩選後總覽改為該學期）、通過率與每學期通過率進度條（文字成績照舊不計入，iOS 把文字成績當 0 分，Android 刻意不同）、學期卡片可收合（預設只展開最新學期）、班級排名放進學期卡片（拿掉獨立的「各學期排名」）；每門課顯示學校給的類別標籤；期中／學期卡片固定顯示平均、班級排名、課程數；排名統一整理成「7/52」。學期平均優先用學校給的值。Model 移到 `grades_models.dart`，元件在 `grades_widgets.dart`，`GradesScreen` 可注入 `session` |
| 1.0.24 | `842758c` | 只升版推 internal，功能和 1.0.23 相同（使用者要求） |

另外：

- google-play-developer MCP 已登記帳號 `niu-app`（金鑰在 `/root/.config/google-play-developer-mcp/service-account.json`），是目前使用中的帳號。
- GA 的 MCP（官方 `analytics-mcp`）2026-10-06 登記在本機 Claude Code 的 user 設定，沿用 Play 的服務帳戶；帳戶與專案資訊只記在本機，不寫進 repo。查資料前需要在 GCP 啟用 Analytics Admin／Data API，並在 GA4 資源把服務帳戶加為「檢視者」。新 session 才會載入工具。GA 看的是 `first_open`／活躍使用者，下載數要看 Play Console。
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

## 校園信箱（0.13.11）

- 使用者選的是**全原生**介面（不是 iOS 的 WebView）。入口在首頁服務的第一格「校園信箱」，路由 `/mail`，深層連結 `niulife://mail`。程式在 `lib/features/mail/`：
  - `numail_client.dart`：API client 和 `MailService` 介面。
  - `mail_session.dart`：登入，以及 vault 的 `mailSession` cookie 封套。
  - `mail_captcha.dart`：解析 SVG、轉成 PNG、用 ML Kit 辨識。
  - `mail_screen.dart`：登入畫面、信件匣、列表、搜尋、多選。
  - `mail_detail_screen.dart`：讀信、附件、回覆／轉寄。
  - `mail_compose_screen.dart`：寫信、附件、草稿。
  - `mail_body_view.dart`：用 WebView 顯示 HTML 信件內容，會自動調整高度並先清理內容。
- 後端是 NUMail（`https://ms.niu.edu.tw`，`mail.niu.edu.tw` 也可以用）的 JSON API，路徑在 `/api` 底下。
  - 驗證方式：`XSRF-TOKEN` cookie 和 `X-XSRF-TOKEN` header 由用戶端自己產生、兩邊要一樣，再加上伺服器發的 `SESSIONID`、`NMV`、`io` cookie。
  - 信件匣名稱要用 **base64url** 編碼，例如 INBOX 是 `SU5CT1g`。
  - 前端的 source map 是公開的（`/NUMail/static/js/main.*.chunk.js.map`），有完整原始碼可以參考。
- 用到的 API：
  - `GET /box`：信件匣和未讀數。
  - `GET /mails/box/{b64}?page&sort=date&asc=false`：信件列表，每頁 20 封。
  - `GET /mails/search?all=&box=`：搜尋。
  - `GET /mails/box/{b64}/{uid}`：讀信，回傳 `mailGroup[0]`。**讀信不會自動標成已讀。**
  - `POST /mails/box/{b64}/{uids}/flags {flags:["Seen"]}`：標成已讀，取消已讀用 `DELETE .../flags/Seen`。
  - `POST .../move {dstBox}`：搬移。不在垃圾桶和草稿裡的信，「刪除」等於搬到 Trash；`DELETE /mails/box/{b64}/{uids}` 是永久刪除。
  - `GET .../attachment/{partId}`：下載附件。
- 寫信流程：
  1. `POST /draft {inReplyTo, references}` 建立草稿，回傳 `{id}`。
  2. 附件：上傳新檔用 `POST /draft/{id}/attachments`（multipart 欄位名 `file`）；轉寄原信附件用 `POST /draft/{id}/attachments/append {attachmentId, cid}`。
  3. 寄出用 `POST /draft/{id}/send {receiver, cc, bcc, subject, type, body}`，存草稿用 `POST /draft/{id}/save`，捨棄用 `DELETE /draft/{id}`。
  4. 編輯既有草稿時，先用 `GET /draft/uid/{uid}` 取回內容。
- **寄信不會自動重送。** 如果送出後逾時或收到 5xx，會丟出 `MailUncertain`，請使用者先查看「寄件備份」。
- 登入：`POST /auth/login {username, password: base64(utf8), captcha}`，接著用 `GET /auth/user` 核對帳號。
  - 一定要輸入驗證碼。驗證碼是 svg-captcha：6 條實心路徑，加上 2 條 `fill="none"` 的干擾線。App 把它轉成 PNG，用 ML Kit（`google_mlkit_text_recognition`）辨識；在登入畫面上，辨識結果會預先填好，使用者可以修改。
  - 自動登入最多試 3 次：登入學校時順便建立，或者用「記住登入」存的帳密。
  - 錯誤訊息的對應方式照 iOS 版 `MailService.swift`，包含 2FA。
- 2026-10-01 用使用者提供的 session 做過**唯讀**實測：信件匣、列表、讀信、搜尋都正常，讀信後未讀狀態沒有改變。**真實帳密登入、ML Kit 辨識率、寄信、上傳附件、搬移和刪除都還沒在真機上測過。**
- 示範模式用 `DemoMailService`，資料存在記憶體裡。
- 0.13.12 修正的問題：
  - **不要在信件內容的 WebView 開 `useShouldInterceptRequest`。** 在 Android 上開了之後，`initialData` 會載入空白頁，信件內容整個不見（在模擬器上已確認）。外部圖片改成由 `sanitizeMailHtml(remoteImages: false)` 直接拿掉 `src` 來封鎖。
  - 搬移、刪除、標記這類修改操作，伺服器回傳 2xx 加純文字，例如 `OK`，**不是 JSON**；只要是非 GET 的請求，就以狀態碼判斷成功。
  - 右上角的按鈕改成 `MailWebScreen`：在 App 內打開學校的 NUMail 手機版，並帶入原生登入取得的 cookie。
- 0.13.13 的改動：
  - 寬版信件會用 CSS `zoom` 縮小到螢幕寬度。**Android WebView 的 `innerWidth` 會被寬內容撐大**，所以畫面寬度改由 Flutter 端量好，用 `VIEW_WIDTH` 注入頁面。
  - 縮小時信件上方會顯示「原始大小」，打開 `MailOriginalScreen`：全螢幕顯示，可以雙指縮放。
  - 信件列表改成每頁 20 封，用上一頁、下一頁切換，點頁碼可以跳頁。原本的捲到底自動載入已經拿掉。
- 0.13.14：Word／Outlook 產生的信會把圖片寫成行內 `style="width:6.5in;height:3.2in"`，優先權高過 `height:auto`，被 `max-width` 縮窄後就變形。`sanitizeMailHtml` 現在只要圖片有寬度，就拿掉固定高度，改用 `aspect-ratio: auto w / h`；CSS 另外加 `object-fit:contain` 當保險。已在 Chrome 以 390px 寬驗證各種寫法的比例都正確。
- 這台機器有 Android 模擬器：`/opt/android-sdk/emulator/emulator -avd niu_api36 -no-window -gpu swiftshader_indirect`，可以用示範帳號登入測試 UI。

## 導覽與 UX（0.13.15）

- 三個主分頁改用 `StatefulShellRoute`，建法集中在 `CampusShell.route(...)`（`lib/app/campus_shell.dart`）。分頁本體是 `PageView`，可以左右滑；三個 branch 都設 `preload: true`，滑動時才不會看到空白頁（代價是啟動時就會載入 M 園區課程列表）。
  - 每個分頁的狀態會保留，例如課表選的星期幾。
  - 不在首頁時，返回鍵會先回首頁；在首頁再按一次才離開 App。
  - 點目前所在的分頁，會回到該分頁的第一頁。
- 分頁內要開新畫面時，記得推到 **root navigator**（`rootNavigator: true` 或 `context.push` 頂層路由），不然新畫面會被包在可以滑動的分頁裡。
- 測試裡用 `scrollUntilVisible` 時要指定 `scrollable:`，因為 `PageView` 本身也是一個 Scrollable。
- 課表**不做**左右滑換日，會和分頁的滑動衝突。
- 課程詳情的 6 個分頁改成 `PageView`，可以左右滑；只在滑到或點到時才載入，看過的分頁會保留。
- UX 檢視的結論（2026-10-02）：
  1. 頁首統一：0.13.18 已處理。`NiuScrollPage` 全部改用單列 `SliverAppBar`，跟 `NiuAppBar` 一樣；主分頁的標題用 `headlineSmall`、不顯示返回鍵。
  2. 主分頁上方留白：0.13.17 已處理。
  3. M 園區的課程代碼、4. 首頁姓名出現兩次、5. 今天課上完後的顯示：**使用者決定維持現狀，不要再提。**
  7. 郵件包裹要先填收件人：使用者後來改主意，1.0.5 已改成自動查詢自己的郵件（見「郵件包裹」）。
  6. 請假頁的重新整理：0.13.18 已處理。右上角一個按鈕加下拉更新，`refreshAll()` 依序讀統計和紀錄（紀錄維持目前頁數）；讀統計時按返回取消，就不會接著讀紀錄。

## 校務系統成績（0.13.16）

- 成績頁（`lib/features/grades/grades_screen.dart`）走 `AcademicPortalScreen`：先開 acade 的 `MainFrame.aspx`，再點選單 `menuLabel`，然後用 `gradeExtractScript` 讀 DOM。
- **acade 的 `MainFrame` 一直載著 `timeoutFrame`（`timeout.aspx`），高度是 0，裡面有密碼欄。** 以前 `portalInteractionScript` 把它當成可見的登入框，所以三個分頁都卡在「請在學校網頁完成驗證或登入」。現在大小為 0 的 frame 和它底下的所有 frame 都不檢查。
- 期中（GRD5131）和學期（GRD5130）會同時載入兩頁：
  - `mainFrame` 是 `_01`，查詢頁，也有 `#DataGrid`，欄位是 學年期／系所／學號／姓名。
  - `viewFrame` 是 `_02`，結果頁，欄位是 序號／學年度／學期／選別／中文課名／成績。
  - 擷取時要挑表頭有「成績」的那頁，而且要等 `readyState === 'complete'`。結果頁沒有「xxx 學年度第 x 學期」字樣，學期名稱改從每列的學年度和學期組出來（`GradeCourse.semesterLabel`）。
  - 成績還沒上傳時是「未上傳」；排名還沒出來時頁面寫「第 名」，App 會當成沒有排名。
- 歷年成績的選單會導到 `MenuRedirect.aspx`，再用 `window.open` 開 `ccsys.niu.edu.tw/MvcTeam/Tutor/StudentCourseScoreSso?GUID=…`（App 的 `onCreateWindow` 會在同一個 WebView 載入），最後落在 `StudentCourseScore`，讀 `#accordion修課紀錄`。一年級上學期的帳號，這頁本來就是空的。
- 驗證方式：用使用者提供的 acade cookie，以 headless Chrome 透過 DevTools Protocol 重現 App 的輪詢流程（導覽、檢查、點選單、擷取），三個分頁都能在 2 到 5 秒內讀到資料。**還沒在 App 裡用真實帳號實測過**；App 是用 SSO 換 GUID 登入，沒辦法直接帶 cookie 進去。

## 成績與在學證明快取（0.13.17）

- 成績、在學證明加了快取：
  - `PortalSnapshotCache`（`lib/core/session/portal_snapshot_cache.dart`）存在 vault 的 `portalCache`，綁帳號，登出時清掉。key 有 `grades.midterm`、`grades.finalTerm`、`grades.history`、`registration`。
  - `AcademicPortalScreen` 新增 `cacheKey`：打開時先顯示上次的資料，上方用 `NiuSyncStatus` 顯示「正在更新」，背景照常向學校讀取，讀到後換成新資料並更新快取。讀取失敗、逾時或學校要求登入時，保留舊資料並顯示「更新失敗，顯示上次的資料」和「再試一次」。沒有快取時，行為和以前一樣。
  - 在學證明的 PDF 是直接向 ccsys 的 `StudyProved/{學號}` 下載，不靠 WebView session，所以顯示快取時也能用。

## Google Analytics（0.13.19）

- 用 Firebase Analytics（`firebase_core`、`firebase_analytics` 套件會帶入原生 SDK，不需要另外加 BoM）。程式在 `lib/core/analytics/app_analytics.dart`。
- **只送固定的名稱**：
  - 畫面：路由路徑或主分頁，例如 `home`、`grades`、`library_spaces`。
  - 功能和結果：`login`／`login_failed`(reason)、`mail_login`(result, captcha: as_read／edited／unread／two_factor)、`mail_send`、`attendance`(outcome)、`leave_apply`、`event_register`／`event_cancel`／`event_update`、`library_reserve`／`library_cancel`、`certificate_open`、`schedule_export`、`notification_setting`。
  - 錯誤：`load_error`(page = `AcademicPortalScreen` 的 title, reason)。
  - **絕對不要**放進帳號、學號、姓名、成績、課名、信件主旨或任何學校回傳的文字。
- 不收集的情況：debug 建置、商店截圖建置、示範模式、使用者在「設定 → 隱私 → 分享匿名使用統計」關閉時（預設開啟，整列都可以點）。
- Manifest 預設 `firebase_analytics_collection_enabled=false`，App 讀到使用者的選擇後才開啟，所以使用者關閉後重新啟動也不會送資料。廣告 ID、AdServices、Install Referrer 權限都已移除，也關閉了自動畫面追蹤。
- 驗證方式：用 release 版搭配 `adb shell setprop debug.firebase.analytics.app me.windless.niulife`，在 logcat 的 `FA` 看「Logging screen view」。已確認開啟時會上傳（204），關閉後切換頁面、重新啟動都是 0 筆。
- **Play Console 的資料安全性表單要配合更新**（使用者處理）。

## 捷徑、小工具與上課中通知（1.0.1）

- **App 捷徑**（長按圖示）：`res/xml/shortcuts.xml` 有四個：快速點名、課表、M 園區、圖書館入館碼，分別開 `niulife://attendance`、`schedule`、`moodle`、`library`。圖示是 `drawable/shortcut_*.xml`（自適應圖示，淺藍底加主色圖案），圖案來自 Material Icons Round（Apache 2.0）。
- **小工具**（配色都在 `values/widget_colors.xml`，有深色版本）：
  - 「快捷列」（`QuickWidget.kt`，4×1）：點名、課表、M 園區、入館碼四個按鈕。
  - 「下一堂課」（`NextClassWidget`，2×2）：顯示上課中或下一堂；今天沒課了，就顯示 7 天內下一個有課的日子。
  - 「今日課表」（`ScheduleWidget`，4×3）：今天的課，底部有「快速點名」和「入館碼」按鈕。
  - 課表類的小工具會用 `WidgetClockReceiver` 加 `wakeBy`，在上下課時間點和半夜更新。
  - **RemoteViews 不能用單純的 `<View>`**，用了小工具會顯示 Can't load widget；間距請用 margin。
- **原生端的課表副本**：小工具、上課提醒、上課中通知都讀 `ScheduleStore` 的 snapshot。`CampusNotifications.refresh()` 每次都會呼叫 `_saveSchedule()`，只要有課表和學期日期就寫入（以前只有開啟上課提醒時才寫，所以小工具一直顯示「同步課表」）。
- **快速點名的入口**是 `AttendanceEntry`：先等 M 園區登入恢復，成功就直接開掃描器，只有真的沒登入時才顯示 M 園區登入。以前冷啟動會停在 M 園區頁面。
- **上課中通知**（`ClassInProgress.kt`）：
  - 「通知設定 → 上課中通知」，預設關閉；開啟時跟上課提醒一樣，會把課表和學期日期寫進原生端（`CampusNotifications.setClassNow`）。
  - 上課時顯示一則低優先、常駐的通知：課名、教室、幾點下課、系統倒數，以及當天下一堂。下課時用 `setTimeoutAfter` 自動消失。
  - 連續節次在 `scheduleBlocks` 已經合併成一個區塊，所以只會顯示一則通知。
  - 在模擬器上把時間調到上課時段驗證過：會顯示、下課會消失、會自動接下一堂。
- **鬧鐘都改用 `AlarmManager.wakeBy`**（在 `ScheduleStore.kt`）：
  - 不精確的鬧鐘最多會延遲「距離觸發時間的 75%，上限 1 小時」。以前上課提醒排在幾天後，可能晚一小時才響。
  - 現在每次只設在剩餘時間的 1/1.75 處，響了之後再排更近的一次，最後一步不到一分鐘，最多晚 45 秒。
  - 不需要精準鬧鐘權限。Doze 仍可能延後。
- 公車功能確定不做，`lib/features/bus` 和測試已刪除。

## 建置工具（1.0.4）

- 依 Play Console 的建議，升級到 Flutter 3.47.5 範本使用的版本：**AGP 9.1.1、Gradle 9.3.1、Kotlin 2.4.0**，google-services 外掛升到 4.4.4。Flutter 支援的 AGP 最高是 9.2，不要升到 9.3 以上。
  - **升級建置工具時，`toolchain.json` 要一起改**，`tool/check_toolchain.py` 會比對，CI 也會檢查。
  - Gradle wrapper 的 `distributionSha256Sum` 要用 Gradle 官方公布的值。
  - AGP 9 預設開啟最佳化資源縮減（build 產物裡有 `optimized_processed_res`）。
  - `flutter_inappwebview_android` 1.1.3（2024 年後就沒更新）還在用 `proguard-android.txt`，AGP 9 預設不允許，所以 `gradle.properties` 加了 `android.r8.proguardAndroidTxt.disallowed=false`。插件更新後就拿掉。
  - `android.builtInKotlin=false`、`android.newDsl=false` 是 Flutter 遷移工具加的，先保留。
- **無邊框畫面**：`MainActivity.onCreate` 呼叫 `WindowCompat.enableEdgeToEdge(window)`（需要 androidx.core 1.17.0），讓 Android 14 以下也跟 15 以上一樣畫到系統列底下。
- 這台機器多了 Android 14 模擬器 `niu_api34`，可以測舊版 Android。release 版在上面驗證過：示範登入、主分頁、信件底部按鈕、設定頁捲到底，都沒有被系統列遮住。
- 發版指令請整串用 `set -e`。曾經發生驗證失敗，但後面不同行的 commit／push 還是執行，結果推了一個 CI 會失敗的 commit（`306e4d2`）。

## 郵件包裹（1.0.5）

- `lib/features/postal/postal_screen.dart`。學校郵務系統（`ccsys2.niu.edu.tw/GA/Postal/`）是公開查詢，不帶學校帳密。一次查詢會同時查三種狀態（學校表單一次只能查一種），狀態篩選在本機做。
- 跟 iOS 的 `PostalQueryViewModel.prepare` 一樣，打開頁面時用 profile 的 `chName` 自動查詢。
  - `chName` 等於帳號時視為還沒有姓名（profile 還沒載入時會這樣），不查詢。
  - 監聽 `CampusSession`：profile 晚到或改名時，只有表單還是自動填的狀態（沒手動改姓名、沒填手機或郵件號碼）才會重新查詢，不會蓋掉使用者輸入的條件。
  - 結果是自動查的，會顯示「依登入姓名查詢」。
- 和 iOS 的差異：iOS 把自己的包裹和「其他查詢」分成兩個畫面；Android 維持同一個表單，改姓名就能查別人。

## 程式架構整理（1.0.6）

完整說明在 `docs/android-flutter-architecture.md` 的「結構」一節。重點：

- `lib/` 分四層：shared → core → features → app，下層不能引用上層。`tool/check_architecture.py` 會檢查，`verify.sh` 也會跑。
- **示範模式**：每個功能有自己的 `*_demo.dart`（例如 `postal/postal_demo.dart`），原本集中的 `features/demo/demo_services.dart` 已刪除。示範用 PDF 與結果文字在 `core/demo/demo_documents.dart`。
- 校務系統 WebView 畫面從 `core/web` 搬到 `features/academic_portal/`。
- Model 不放在 screen 檔：`events/event_models.dart`、`schedule/schedule_models.dart`；設定頁拆出 `privacy_screen.dart`、`credits_screen.dart`；GitHub raw 下載在 `core/network/public_content.dart`；校曆 providers 在 `academic_calendar/calendar_providers.dart`。
- 測試資料夾對應 `lib/`（`test/features/<功能>/`），共用假物件在 `test/support/fakes.dart`，HTML／jsdom 在 `test/fixtures/`。
- 2026-09-30 的 UI 檢視紀錄移到 `docs/archive/`。
- 1.0.7 拆開超過 1000 行的畫面檔，現在最大的是 `academic_portal_screen.dart`（989 行）：
  - 圖書館預約：步驟卡片、日期條、時段在 `space_booking_steps.dart`，底部預約列與確認頁在 `space_booking_bar.dart`，我的預約卡片在 `space_reservation_card.dart`。
  - M 園區：一個畫面一個檔，`moodle_screen.dart`（分頁）、`moodle_courses_screen.dart`（課程列表與 `MoodleList`）、`moodle_course_screen.dart`、`moodle_module_screen.dart`、`moodle_forum_screen.dart`、`moodle_assignment_screen.dart`；`pushMoodle`、`openMoodleUrl`、附件按鈕在 `moodle_links.dart`。
  - 請假申請的節次與送出確認頁在 `leave_application_sheets.dart`；信件列表項目與分頁在 `mail_list_widgets.dart`。
- 還沒處理、可以接著做的：
  - `moodle` 和 `attendance` 互相引用（課程頁開點名、點名用 M 園區 repository）；`authentication/login_screen.dart` 登入後直接建立 M 園區、活動、信箱、圖書館的 session。目前可運作，要拆的話可以改成在 app 層註冊。

## 請假頁（1.0.9）

- 統計卡（`LeaveTypeStatistics`）：有請假的假別做成等高卡片，依寬度 1～3 欄，每列用 `Expanded` 填滿（4 種排 2 × 2）；0 節的假別合併成一行灰字。假別名稱用 `leaveTypeShortName` 去掉括號裡的子類別，例如「產假（產前假／陪產假…）」只顯示「產假」，完整名稱留在 Tooltip 和讀屏。
- 明細打開時，若沒有簽核流程、或請假紀錄比明細新，就自動讀取一次（`_autoLoaded` 避免失敗時一直重試），和 iOS 的 `.task { loadDetail }` 一樣。
- 簽核流程照 iOS 的 `LeaveApprovalTimeline`：多讀「簽核人」「簽核意見」和流程名稱（欄位存在才讀）；已簽核打勾、簽核中時鐘、退回紅色圖示；學校自動填的「(申請送出)」「(已簽核，查無簽核意見。)」「(自動歸檔)」不顯示；最新的退回意見放在明細最上面。
- 1.0.11 請假節次：`LeavePeriodEntry`／`leavePeriodEntries`（`leave_application_data.dart`）依表頭讀節次表（請假日期、請假節次、課程名稱、授課教師…），沒有表頭時依格子內容判斷；申請表另存 `periodHeaders`。`LeavePeriodSchedule`（`leave_widgets.dart`）依日期分組並合併同一堂課的連續節次。節次選擇格照 iOS 拆成教師／課名／教室三行。**真實帳號的表頭與格子內容還沒驗證**，讀不到時會退回用格子內容判斷。
- 學校實際有 10 種假別（含「心理健康假」），示範資料改成 10 種，並多一張「退回」的假單（`D1150921`）。

## 整週課表（1.0.12）

- `lib/features/schedule/schedule_week_view.dart`：橫軸星期（一～五，週末有課才出現）、縱軸節次（只顯示整週第一堂到最後一堂的範圍）。用 `scheduleLessons(..., mergeConsecutive: true)` 把同一堂課的連續節次合成一格；顏色依課名雜湊，同一門課每天同色；今天的欄位淡色底、上課中的格子加外框；點格子開底部面板（時間、教室、老師、開啟 M 園區課程）。
- 1.0.14 重新設計：`ScheduleWeekView(now:, height:)` 由課表頁傳入台北時間與可用高度（螢幕高度扣掉約 290dp 的標題列、切換、底部分頁與同步列），列高在 58dp～93dp 間填滿畫面；星期下方有日期；今天整欄淡藍底；`_NowLine` 依節次時間把紅線放在現在的位置（下課時間停在節次交界，第一節前、最後一節後不顯示）；課程格是較深的課程色底＋左側色條；**所有天數都塞進螢幕寬度，不再左右捲動**，欄寬小於 56dp 時字縮小一級。
- **模擬器每次開機都回到舊快照**：用 `-no-snapshot-save` 啟動，所以先前裝的 App 不會保留，開機後是快照裡的 1.0.1，截圖前一定要先 `adb install -r` 最新 APK（`smoke_android.py` 不加 `--no-install` 會自動安裝）。
- 這台模擬器的快照帶著 `wm density 210`（畫面像兩倍大的平板），每次開機都會回到 210。檢查版面前先 `adb shell wm density reset` 回 420（真實手機的大小）。`smoke_android.py` 在兩種密度都跑過。
- 課表頁上方的「單日／整週」切換存在 SharedPreferences 的 `scheduleWeekView`。

## 公告（1.0.12）

- 來源是 `app-content/announcements.json`，格式與發布方式寫在 `app-content/README.md`。**使用者發公告只要改這個檔、revision 加一、推到 main**，不用發新版。
- `lib/features/announcements/`：`announcement_repository.dart`（格式驗證、revision 只能往前、快取在 application support、一小時內不重讀）、`announcement_board.dart`（首頁卡片＋一次性彈窗；關掉的卡片與看過的彈窗用 SharedPreferences 記 id）、`announcements_screen.dart`（設定 → 公告、公告內容頁）。
- 每則可設 `start`／`end`（台北日期，含當天）、`minVersion`／`maxVersion`（例如只對舊版顯示「請更新」）、`popup`、HTTPS 連結。
- App 內建的公告清單永遠是空的（內建的公告在不更新的舊版上會一直留著）。測試只檢查 `announcements.json` 格式；CI 已加上 `app-content/**` 觸發，推錯格式 CI 會失敗，App 則繼續用上一份有效內容。
- 商店截圖建置（`NIU_STORE_SCREENSHOTS`）不顯示公告。
- `smoke_android.py` 會自動按掉公告彈窗。
- 2026-10-05 發過一則測試公告（id `2026-10-05-test`，revision 2），同一天已刪除（revision 3，清單是空的）。下一則公告的 revision 從 4 開始。

## 平板（尚未優化，2026-10-05 檢查）

- 在 210 密度（約 820×1830dp，接近 10 吋平板）和橫向下看過：功能正常，但內容整排拉滿寬度；橫向時首頁很矮、校園服務要捲動；仍是底部導覽列；Play 沒有平板截圖。整週課表在平板上表現最好。
- 使用者 2026-10-05 決定**列為待處理事項，先不做**（見「可以接著做的事」）。

## 官網（2026-10-05）

- 獨立 repo：**windlessme/niu-life-site**（本機 `/root/niu-life-site`），**Astro + TypeScript + GSAP ScrollTrigger**（2026-10-05 從手寫 HTML 改寫，使用者要求換開發技術），輸出純靜態網站，推到 `main` 由 GitHub Actions 建置並部署到 GitHub Pages。結構與開發方式見該 repo 的 README。
- 正式網址：**https://niu-life.app/**（2026-10-05 上線，強制 HTTPS，Let's Encrypt 憑證涵蓋 www；`www` 轉到主網域）。DNS 在 Cloudflare，紀錄必須維持「僅 DNS」（灰色雲朵），否則 GitHub 無法續約憑證。
- 首頁是捲動敘事（參考 nycu.life 的架構，插畫與文案自製）：開場貼紙飛進手機、功能區 01～06 固定切換、許願池連回報表單。**一律播放完整動畫，不參考系統的「減少動態效果」**（使用者 2026-10-05 決定：他的手機和電腦都有開，看不到動畫）。功能區截圖用商店截圖模式在模擬器拍（見網站 README）。
- 隱私權頁網址是 **https://niu-life.app/privacy**（`/privacy.html` 也可以）。
- **App Links（1.0.16）**：網站 `/.well-known/assetlinks.json`（Play Console 產生，憑證是 Google 保管的簽署金鑰，只有從 Play 安裝的 App 會驗證通過；debug／預覽版不會，屬正常）。Manifest 宣告 `https://niu-life.app/download` 與 `/open/` 前綴並 `autoVerify`；`lib/app/deep_links.dart` 的 `campusDeepLink` 把 `/download` 導到首頁、`/open/schedule|attendance|library|mail|moodle|calendar` 導到對應頁（完整網址或只有路徑都接受）。網站對應的說明頁在 niu-life-site 的 `src/pages/open/[feature].astro`，新增功能時兩邊一起改。在模擬器上用 `adb shell am start -a android.intent.action.VIEW -d <網址> me.windless.niulife` 驗證過路由。
- **下載連結 https://niu-life.app/download**：手機自動前往 App Store／Google Play，電腦顯示按鈕與 QR Code；可加 `utm_*` 參數，Android 會帶進 Play 的安裝來源。海報、社群貼文用這個。
- 網站 GA：`G-TQSN4NFDVD`（與 App 同一個 Firebase GA4 資源的網站串流 16044768167），記頁面瀏覽與 `store_click`；隱私權頁最後一節說明網站本身的統計。
- **待使用者處理（1.0.0 已審核通過）**：Play Console 的隱私權政策網址改成 `https://niu-life.app/privacy`；商店資訊的聯絡電子郵件改成 `hi@niu-life.app`、網站填 `https://niu-life.app/`（後兩項可用 MCP `details_patch` 代改，使用者同意後再做）。
- **iOS 版要配合的（qian403 維護，不在本 repo）**：App Store Connect 的隱私權政策網址改 `https://niu-life.app/privacy`、支援網址改 `https://niu-life.app/`；iOS App 與 iOS repo 的 `docs/privacy-policy.md`、`docs/support.md` 的信箱 hi@chien.dev 改成 hi@niu-life.app。共用政策的 iOS 段落依 iOS repo 2026-10-05 版政策改寫，iOS 做法有變動時要同步更新網站上的政策。Android 這邊 1.0.0 已審核通過。
- 隱私權政策（iOS、Android、網站共用）直接寫在網站 repo 的 `src/content/privacy.md`，改完推到 niu-life-site 的 `main` 就會部署。
- 首頁的功能介紹是手寫的；App 加了使用者看得到的大功能時，順手更新網站的 `index.html`。

## 重要決策

- **不架後端。** 需要遠端內容時沿用 credits 的做法：GitHub 上的靜態 JSON，加上 App 內建的離線版本和 revision 號碼。
- **In-App Updates 只用彈性更新。** 同一個 versionCode 只問一次；只有 release 版而且是從 Play 安裝的才會檢查，debug 預覽版、截圖版、側載版都跳過。下載完成後顯示 SnackBar「重新啟動」，透過 `MaterialApp.scaffoldMessengerKey`。
- **通知功能對齊 iOS，不多做。** 例如假日也不會略過上課提醒，提醒時間固定 10 分鐘。
- Play 主題圖片（1024×500）建議用 App 的淺色配色：漸層 `#F2F3F7` 到 `#E5EEFC`，標題 `#15171C`，強調色 `#0A62D0`。

## 不做的功能

- **分享 App 的 QR Code**：使用者 2026-10-04 決定不做。

- **代點名**（掃描點名後幫其他同學點名）：使用者問過，Claude 拒絕，沒有後端的版本也不做，使用者已同意不做。不要再提或規劃。
- 公車到站資訊：已放棄（見 1.0.1）。
- UX 檢視第 3、4、5 項：維持現狀（見「導覽與 UX」）。

## M 園區網頁登入（1.0.18 試過，1.0.19 還原）

- 1.0.18 曾把網頁登入改成隱藏 WebView 依序試 Cookie → 自動登入金鑰 → 用記住的帳密填 M 園區登入表單，並把所有隱藏登入排隊執行、掃描器打開就先登入。**使用者 2026-10-06 回報讀取 M 園區課程變慢、甚至無法讀取，要求回到原本架構，1.0.19 已還原。** 不要再用同樣做法。
- 原本問題仍在：自動登入金鑰同一使用者 6 分鐘只能取一次（Moodle `autologinmintimebetweenreq`），每次開網頁都取新金鑰，所以第二次起會落到登入頁。要再處理時先跟使用者討論做法，避免拖慢課程讀取（例如不要排隊、不要在背景預先登入）。
- M 園區網站實測（2026-10-06，使用者提供的 Cookie）：已登入頁面 body 沒有 `notloggedin`、有 `logout.php` 連結；登入頁是 `#page-login-index`、body 有 `notloggedin`，表單 `#login` 有 `username`／`password`／`logintoken`。前面有 Citrix NetScaler 負載平衡（`NSC_*`、`citrix_ns_id` Cookie）。

## 尚未驗證／已知事項


- **郵件包裹偶爾沒有自動查詢**（2026-10-04 觀察到）：在模擬器上全新安裝、登入示範帳號後，有一次打開郵件包裹沒有自動查詢，有顯示「帶入我的姓名」，代表姓名有讀到。同一個 App 程序裡再開一次也一樣。之後重裝重跑 3 次完整流程、同一程序開關 12 次，都正常，找不到原因。`_searchOwnMail` 只在第一個 frame 後和 session 通知時執行；如果再發生，先在它開頭加 log 看是哪個條件提早 return。`smoke_android.py` 會檢查這一步。

- 通知、In-App Updates 都**沒在實機上測過**。In-App Updates 要用 Play 內部測試軌道，而且需要兩個不同的 versionCode 才測得出來。
- `NiuSection` 改成基線對齊、`NiuRow` 的值改成填滿空間，都會影響全 App。只用測試環境渲染確認過幾個畫面。
- 行事曆資料的網址指向 `qian403/NIU-app`，不是本 repo（`calendar_repository.dart` 的 `baseUrl`）。要不要改成自己維護，還沒決定。

## 可以接著做的事

1. **1.0.17 已送審為正式版（2026-10-06）**，等審核結果；審核結束前不要提交新的正式版。
2. 在實機上驗證三種通知和點通知後的跳轉，必要時調整文案或時間。
3. 等使用者把測試人員加進 internal 名單，再推版本號更大的 build，在實機上測 In-App Updates。
4. 用 release 版上 Play 內部測試軌道，驗證 In-App Updates。
5. 在實機上測試校園信箱：登入時驗證碼的辨識率、寄信（先寄給自己）、附件上傳和下載、搬移和刪除。
6. 在實機上用真實帳密測試圖書館登入，包含登入學校時順便建立 session，以及在畫面上手動輸入密碼。
7. 決定行事曆資料來源要不要改成本 repo。
8. **平板優化**（使用者 2026-10-05 列為待處理）：
   - 第一階段：所有列表與詳情頁內容最寬約 720dp 置中；寬螢幕（≥600dp）把底部導覽列換成左側導覽列；首頁寬螢幕改兩欄（左：今天與快速點名，右：校園服務）；平板預設整週課表。
   - 第二階段：校園信箱、M 園區、請假紀錄改左右分欄（列表＋內容）；製作 7 吋與 10 吋平板商店截圖上傳 Play。
   - 檢查方式：模擬器 `wm density 210`（約 820dp 寬）並切橫向（`settings put system user_rotation 1`）。
