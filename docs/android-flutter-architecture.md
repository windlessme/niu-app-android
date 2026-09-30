# Android 架構與維護

工具版本以 [toolchain.json](../mobile/toolchain.json) 為準。執行、驗證及建置步驟見 [mobile/README.md](../mobile/README.md)。

## 結構

- `mobile/lib/app/`：啟動組裝、go_router 路由及三個主頁籤（首頁、課表、M 園區）。
- `mobile/lib/features/`：依功能分組的畫面、presentation models、repositories。
- `mobile/lib/core/`：HTTP、校務 WebView、Session、憑證儲存及 Android 橋接。
- `mobile/lib/shared/`：語意色彩、字級、間距、圓角及共用 UI 元件。
- `mobile/android/`：課表 Widget、提醒、快捷與文件預覽／儲存。

Riverpod 管理校曆資料來源與非同步狀態；CampusSession 使用 ChangeNotifier。頁面 UI 使用 StatefulWidget，詳情沿用 Navigator。校務資料由手機直接連學校，公開校曆／致謝讀取 GitHub；本庫沒有自建校務後端。

## 登入與資料界線

校務 SSO、舊教務網頁、Moodle API、Moodle 網站與活動網站有各自的認證。SSO 過期不清除其他服務的有效憑證。主動登出才完整清除帳號資料；非同步回應以 epoch 避免登出後寫回。

- [Session 契約](../mobile/lib/core/session/README.md)
- [課表平台橋接契約](../mobile/lib/core/platform/README.md)
- [登入頁公開來源與 DOM fixture](sso-login-capture-findings.md)
- [Android 隱私政策](android-privacy-policy.md)

帳密使用裝置安全儲存；不得加入版本庫、測試日誌或公開下載目錄。點名、作業提交與活動報名不自動重送。校方網頁解析失敗時提供明確狀態與校方頁面入口。

校務頁首次仍透過 SSO GUID 建立登入。成功讀取受保護資料後，同一帳號、同一次 Session 的後續查詢會優先沿用 WebView Cookie；若校方回傳登入逾時，僅重新建立一次 GUID 連線。這個可重用狀態只保留於記憶體，登出後失效，不快取或重用 GUID。活動頁還原自己的 Cookie 後直接開啟指定頁面；初次 SSO 登入後，Moodle 與活動認證並行建立。

有原生資料畫面的校務查詢使用共用載入狀態遮住中間網頁，底層 WebView 保留正常尺寸以供 DOM 解析；使用者可隨時開啟校方頁面。偵測到可見的驗證或登入控制項時顯示校方畫面，不自動解驗證。框架 DOM 就緒即喚醒導覽，不必等待其他框架與圖片全部載入；離開畫面或 App 進入背景時暫停輪詢與逾時計時。

畢業門檻首次讀取後，以 `graduationCache` 儲存帳號、UTC 更新時間與校方解析結果於裝置安全儲存。後續開啟優先顯示快取，僅手動更新時連線；離線或 SSO 過期仍可查看，更新失敗／返回不清除舊資料。快取不跨帳號，登出立即清除記憶體並等待進行中的寫入後清除儲存；損壞或不支援版本的快取視為未儲存。畫面保留校方未知值，不以零代替。

## 設計系統

登入與 iOS 相同：原生表單輸入學號與密碼後，`SchoolLoginDriver` 在不可見的 WebView 開啟校方 SSO 登入頁，填入帳密，等校方的人機驗證（Turnstile）讓「登入」按鈕可按後按下一次，再讀取 `niu_sso_token` 或校方錯誤彈窗。登入頁先被「正在登入校務系統」遮住，8 秒後或使用者點選時顯示，讓需要互動的驗證可以手動完成；App 不處理驗證本身。Token 必須經 `Authorization/info` 伺服器身分驗證後才能建立 Session，接著並行建立 M 園區與活動系統登入。帳密錯誤會清除已記住的帳密；密碼到期提供修改密碼連結。`SchoolReauthorization` 以同一套流程在背景用已記住的帳密恢復 Session，最多等待 25 秒。活動登入失效時也只嘗試一次帳密恢復，不重送報名操作。

`NiuColors` 為 ThemeExtension，採三層表面：canvas（頁面）→ surface（卡片、導覽列）→ fill（卡片內的控制項與區塊），另有 ink 三階文字、accent 與 success/warning/error；`NiuHue` 為各功能的識別色，淺深色皆有可讀前景與淡色底。`NiuSpacing`（4pt，頁面邊距 20）、`NiuRadius`（卡片 20）、`NiuSize`、`NiuMotion` 為共用 tokens，字級見 `NiuTheme`。

元件統一放在 `lib/shared/`：頁面框架 `NiuScrollPage`（主分頁用 large、次頁用 medium 可收合標題列）與 `NiuAppBar`；表面 `NiuCard`、`NiuGroup`/`NiuRow`（分組列表）、`NiuSection`、`NiuWell`；狀態 `NiuLoading`、`NiuEmpty`、`NiuError`、`NiuBanner`、`NiuSyncStatus`；資料 `NiuStat`、`NiuProgressBar`、`NiuKeyValue`、`NiuField`；控制項 `NiuSegmented`、`NiuTabs`、`NiuFilterBar`、`NiuBadge`、`NiuTag`、`NiuSearchField`。圖示只用 `NiuIcons`（Material Rounded）。其他校園服務只從首頁的服務格進入，名稱、圖示與顏色集中在 `features/home/campus_services.dart`。主分頁不顯示返回鍵，其他頁使用 Android 返回箭頭並支援預測式返回；列表底部保留系統手勢區距離。QR 原始影像與白色 quiet zone 是掃描用途的例外。

## 驗證

### 一般學生請假申請

`features/leave/leave_application_screen.dart` 為原生申請表單；
`leave_application_service.dart` 序列化校方表單操作，
`leave_application_scripts.dart` 只在同一個已登入 WebView 的指定校方頁面執行。
假別、民國日期、可選節次與附件限制從校方表單取得，公假選項不提供。
保留校方注意事項的明確同意、節次帶回、附件附加與最終送出的區別。
日期 postback 必須等待上一個表單版本更新完成，不重疊請求。

草稿僅在目前頁面記憶體內，不存入請假查詢快取；離開或登出清除 App 中的草稿。
檔案經系統選擇器讀取，使用者確認後才上傳；App 暫設 10 MB 傳輸上限，
不把校方隱藏欄位的未確認單位當成正式限制。上傳透過分段資料傳入原校方附件表單，
校方回傳附件列表後才標記完成；不自動刪除或重送附件。
送出前再次確認，送出呼叫後立即鎖定重送；新假單號與校方簽核入口就緒才顯示已建立，
其餘情況回到既有查詢確認，不以跳頁或逾時推定成功。校方網頁仍可在同一 WebView 開啟。

`leave_application_test.dart`、`leave_application_screen_test.dart` 與
`integration_test/leave_application_dom_test.dart` 使用合成資料。
真實假單送出、附件保存、各假別完整規則仍需帳號／裝置驗收，不在自動測試中執行。

`mobile/tool/verify.sh` 執行資料同步、工具版本、DOM fixtures、格式、分析與 Flutter 測試。自動化測試使用合成資料，不送出實際校務操作。

- [在學證明裝置驗收](registration-device-checks.md)
- `mobile/integration_test/`：Android 原生橋接、WebView 與 UI 測試。
- `calendar-data/`：校曆原始 JSON、Schema 與離線驗證。

Flutter 所帶 AGP 9 模板與目前 InAppWebView 的舊 ProGuard 設定不相容，故固定 AGP 8.11.1／Gradle 8.14.3／Kotlin 2.2.20。升級時需一起驗證原生套件；建置仍會出現 Flutter 未來支援提醒。

實際校方登入、門禁、點名、報名與文件儲存需要帳號及裝置驗收；fixture 通過不代表已完成端到端驗證。
