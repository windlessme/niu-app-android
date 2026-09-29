# Android 開發紀錄

## 2026-09-29：0.5.2 跨平台Design System

- 先核對iOS遠端HEAD並閱讀Swift實作，完成audit mapping後才收斂Flutter tokens。
- semantic spacing/radius/colors/motion/icons與status/info/filter chips，首頁共用feature card。
- 保留資料／登入／路由結構，Android使用PredictiveBack轉場builder。
- 詳見 `design-system-cross-platform-audit.md` 與 `design-system-alignment-0.5.2.md`。

## 2026-09-29：0.5.1 自動記住帳密

- 移除登入勾選框，開啟登入流程時啟用加密保存，校方驗證成功才保存同帳號資料。
- 等待安全儲存還原完成後才處理登入Token，避免非同步初始化與保存交錯。
- 設定忘記與主動登出仍可清除；再次成功輸入帳密登入後重新保存。
- 隱私說明與README同步更新，自動填入不自動提交或處理人機驗證。

## 2026-09-29：0.5.0 註冊資訊／在學證明

- 以使用者授權的校務Session確認真實查詢註冊頁與本人PDF流程，私人樣本不進版本庫。
- 新功能入口置於首頁與校園，重用校務登入與設計系統。
- 詳細實作見 `registration-feature-0.5.0.md`，前次探索見 `enrollment-certificate-discovery.md`。

## 2026-09-29：0.4.3 選擇記住校務帳密

- 依使用者要求提供裝置加密保存及校方登入頁自動填入，預設由使用者選擇啟用。
- 人機驗證仍由使用者完成，保留手動登入提交；設定可清除、登出一併刪除。
- 詳細記錄見 `remember-login-0.4.3.md`。

## 2026-09-29：0.4.2 活動報名介面

- 沿用既有元件調整活動列表／我的報名／詳情與資料更新流程。
- 校方登入及實際報名表單維持原本服務；詳細驗證見 `events-ui-0.4.2.md`。

## 2026-09-29：0.4.1 登入保留

- 啟動時單一 SSO 驗證失效不再完整登出，其他服務憑證與課表保留。
- 新增身分驗證 generation 防止舊回應覆蓋新登入，重新驗證請求合併。
- 詳見 `login-preservation-0.4.1.md`。

## 2026-09-29：0.4.0 後半部頁面

- 課表恢復逐節呈現；既有前半部設計保留。
- 課程詳情／教材／作業改用 root Navigator，詳情不顯示 bottom navigation，返回保留 root 狀態。
- 本次課程六分頁、點名冊與圖書館 UI／更新生命週期調整詳見 `course-detail-library-0.4.0.md`。

## 2026-09-29：0.3.3 課表首次載入與畢業門檻

- 等待 GUID 登入真正跳轉；以文件生命週期與查詢回應確認課表就緒，拒絕舊文件／查詢前空表。
- 畢業門檻改為精簡完成項數摘要、剩餘學分／時數與待處理篩選。
- 全套146項測試與靜態分析通過；詳細見 `first-load-graduation-0.3.3.md`。

## 2026-09-29：0.3.0 Flutter UI 重構

- 依文字規格重構 semantic colors、textTheme、卡片、圓形 Header、搜尋與四分頁導覽，保留 Flutter／Riverpod／go_router／原始 API 與服務。
- 課表時間軸與合併節次、精簡 Moodle 卡片／完整詳情、畢業 Dashboard、校曆標記與搜尋。
- 特別感謝加入 qian403/niu-app；詳細檔案與限制見 [UI 重構紀錄](flutter-ui-redesign-0.3.0.md)。
- Android 16 深／淺色 UI 整合測試通過；320／600px 與 2x 系統字體回歸覆蓋。

## 2026-09-29：0.2.5 活動登入修正

- 0.2.4 的活動 GUID 入口並未確認校方對此帳號提供支援，退回登入頁不等同自動登入完成。
- 改以活動系統實際登入表單建立獨立 Session，與校務登入當次帳密銜接；不保存原始密碼。
- 保留原始活動／我的報名目標，活動 Session 失效時提供重新連接入口。
- 活動轉登入頁時重設導覽去重紀錄，避免登入成功後 ApplyMe 被當成「已嘗試過」而不再導向。

## 2026-09-29：0.2.4 使用便利性調整

- 課表採快取優先；已有同帳號快取時開頁不自動建立校務 WebView，手動更新才查詢。
- 深色模式改為深灰藍背景、分層卡片、較亮的主／次文字與高對比按鈕，Material／Cupertino 共用一致配色。
- 整合校務登入後的 Moodle 認證與活動系統 SSO，減少重複帳密輸入。
- 深色文字對比與大字體首頁測試通過；其餘測試與 APK 發布結果於整合後補記。
- Android 深色首頁合成資料 integration test 通過。登入頁與 AuthGate 的生命週期調整為等待 Moodle handoff 完成，避免 SSO 成功通知過早移除登入頁。
- 活動 SSO 可用性需有效帳號驗證；不可用時保留可操作的獨立活動登入，登入後返回 ApplyMe，不宣稱該分支已免密碼。
- 從舊版升級、只有 SSO Token 而沒有 Moodle Token 的帳號，需透過校方登入頁完成一次帳密登入以建立 Moodle 憑證；之後 M 園區與點名共用儲存的登入狀態。
- 全專案靜態分析與 100 項測試通過，APK 建置／簽署／64-bit ELF 對齊檢查通過。0.2.4 模擬器安裝與冷啟動成功，實際深色首頁截圖已檢視（`/tmp/opencode/niu-dark-024.png`）。

## 2026-09-29：0.2.3 課表與畢業門檻白畫面修正

- 檢查並修正共用校務 WebView 的版面、導覽與資料擷取流程。
- WebView Stack 強制填滿、處理 GUID 中繼頁與 Std002 真正校務入口連結，課表／門檻使用 iOS 對應 Referer；加入獨立 60 秒逾時及可見狀態。
- 課表／畢業門檻擷取腳本支援同來源子框架；無法存取的跨來源框架略過，不阻斷其他框架。
- 課表查詢按鈕未出現時回報尚未就緒，避免將過早執行視為查詢完成；同一文件按鈕只觸發一次。
- 新增直接執行正式 JavaScript 的 DOM fixtures，驗證框架資料、延遲按鈕及單次查詢。
- Android 16／WebView 133 實際執行 `academic_dom_test.dart` 通過：WebView 有可見尺寸，正式課表與門檻腳本能讀出合成校方 HTML 資料。此測試不使用真實校務帳號。
- 課表原生畫面切換測試通過：解析出的課程在有界版面下可顯示分頁與課程時間。

## 2026-09-29：0.2.2 首頁課表型別修正

- 修正 `cachedSchedule?.today() ?? []` 導致迭代元素失去 record 型別、字串 `.where()` 條件成為 dynamic 回傳值的執行期錯誤。
- 使用獨立 Dart 最小案例重現完全相同的 `(dynamic) => dynamic`／`(dynamic) => bool` 錯誤，確認根因。
- 抽出具型別的 `todayCourses` 轉換，無快取時直接回傳空清單。
- 新增 JSON 還原的真實形狀課表 fixture，涵蓋課名／教室空白整理、當前與下一堂、已結束課程及無快取。

## 2026-09-29：0.2.1 登入與圖碼體驗修正

- 移除 App 額外學號輸入欄；只在校方頁面輸入帳密。透過帶 Token 的校方身分 API 取得帳號，不依賴登入前 DOM 或未驗證的 JWT 宣稱。
- 取消快捷入口前額外的「登入後使用」提示頁；先恢復既有登入，有效登入直接使用，確需校方登入時直接呈現登入頁，成功後留在原功能。
- 圖書館 QR Code 明確填滿可用的正方形圖碼區域，保持等比例與白色邊界；借書條碼使用橫向比例，避免以原始圖片像素大小置中造成過小。
- 自訂 PIN／生物識別 App 鎖列為公測階段需求，本次不啟用；校方帳號驗證仍依實際服務要求。

## 2026-09-29：0.2.0 功能整合

- 各校務、Moodle、點名、圖書館、校曆與設定已整合進 App；首頁與四分頁導覽採 iOS 風格。
- 課表支援帳號隔離快取、離線顯示、Widget、本機通知與 ICS 匯出。
- 登出支援持久化待清除標記、程序中斷恢復與跨功能清理；Moodle 登入加密保存並重新確認身分。
- 全專案分析無問題，70 項測試通過；Android MethodChannel integration test 通過。
- 0.2.0 debug APK 建置、簽署及 native ELF 16 KB 靜態檢查通過，已發布公網下載點。
- 模擬器首頁／校曆導覽、點名 deep link 登入保護頁通過；校曆截圖已檢視。
- 完整差異與尚未完成的實測列於 [功能對照](android-feature-parity.md)。校務真實帳號驗證仍缺少測試憑證；自動 OCR 與遠端推播後端未實作。

## 2026-09-28：P0 與 P1 基礎

- 持久工作目錄：`/root/niu-app`。
- Java：OpenJDK 17；Android SDK：`/opt/android-sdk`，已安裝 API 36、build-tools 36.0.0 與 platform-tools。
- Flutter SDK 位於 `/opt/flutter`。工具環境由 `/etc/profile.d/niu-android.sh` 提供，本機 shell 可 `source` 該檔案。
- `mobile/` 提供 Flutter App、Riverpod 資料來源注入、路由與繁體中文校曆介面。
- 公開校曆 assets 由 `mobile/tool/sync_calendar.py` 自現有 `calendar-data/` 同步；讀取時驗證 hash、metadata 與事件 ID。
- P1 基礎包含 SessionCoordinator、CredentialVault、精確網址政策與 Moodle API transport。
- Android package 使用 `dev.niulife.prototype.niu_mobile` 作為開發識別碼；正式上架前需確認永久 ID。release 不使用 debug key 自動簽署。
- 真實 SSO、WebView Cookie、GUID、個人課表與點名串接尚待完成和實機驗證。

### 已執行驗證

- Flutter 3.47.5（revision `6a19cca56475dbfba1478ee68d7bd0c2ef891da1`）、Dart 3.13.4。
- `flutter doctor -v`：Android toolchain 通過，SDK licenses 已接受，Android 16 模擬器已連線。Linux desktop 工具鏈未安裝，與本次 Android 目標無關。
- 模擬器 WebView：`com.google.android.webview` 133.0.6943.137；後續 P1 還需要目前版本 WebView 與不同廠牌真機的組合測試。
- `flutter analyze`：無問題。
- `flutter test`：17 項通過，涵蓋日期／完整性、路由搜尋、登入與登出競態、憑證清除、網址政策與 HTTP 語意。
- `python3 -m unittest discover -s calendar-data/tests -q`：現有 20 項測試通過。
- 校曆 assets 的 canonical source 同步與 SHA-256 檢查通過。
- `flutter build apk --debug`：成功，產物 `mobile/build/app/outputs/flutter-apk/app-debug.apk`。
- `apksigner verify`：debug APK 簽署驗證通過；manifest 確認 minSdk 26、targetSdk／compileSdk 36、versionName 0.1.0、versionCode 1。
- Android 16 模擬器安裝成功，UI Automator 驗證首頁與校曆導覽通過；已檢視校曆截圖，繁體中文、年度選擇與事件列表正常呈現。
- 首次 smoke check 被模擬器的「System UI isn't responding」對話框擋住；確認 App log 沒有 AndroidRuntime crash，關閉系統對話框後重啟 App，重測通過。真機效能與相容性仍待驗證。
- 截圖：`/tmp/opencode/niu-calendar.png`；UI dump：`/tmp/opencode/niu-window.xml`、`/tmp/opencode/niu-calendar.xml`。

### 本機網路注意事項

此主機連接 Gradle 服務的 IPv4 路徑逾時，IPv6 可用。建置時使用：

```sh
source /etc/profile.d/niu-android.sh
cd /root/niu-app/mobile
JAVA_TOOL_OPTIONS=-Djava.net.preferIPv6Addresses=true flutter build apk --debug
```

Gradle 9.3.1 的官方 distribution 已透過 curl 下載、以官方 SHA-256 驗證並放入本機 wrapper cache。此處的 IPv6 設定只用於本機建置，不改寫 App 網路行為。

### WebView 建置相容性決策

Flutter 3.47.5 模板預設 AGP 9.1.0，但目前解算到的 `flutter_inappwebview_android` 1.1.3 使用 AGP 9 已移除的 `proguard-android.txt`，造成 configuration 階段失敗。

專案改採 AGP 8.11.1／Gradle 8.14.3／Kotlin 2.2.20，明確套用 Kotlin Android plugin；Gradle wrapper 固定官方 SHA-256。Flutter 3.47.5 要求 Gradle 至少 8.14、Kotlin 至少 2.2.20，因此初次選用的版本已調整。未修改套件快取或略過依賴驗證。後續升級 AGP 9 前需確認全部原生套件相容。

此組合符合目前最低支援版本，但 Flutter 會印出未來停止支援的版本提醒；需要在後續套件升級時一起追蹤，不能將建置描述為「零警告」。
