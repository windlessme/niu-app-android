# Android 架構與維護

工具版本以 [toolchain.json](../mobile/toolchain.json) 為準。執行、驗證及建置步驟見 [mobile/README.md](../mobile/README.md)。

## 結構

- `mobile/lib/app/`：啟動組裝、go_router 路由及四個主頁籤。
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

## 設計系統

`NiuColors` 為 ThemeExtension，區分 page/card/control/navigation surfaces 及狀態色；`NiuSpacing`、`NiuRadius`、`NiuMotion` 為共用 tokens。畫面使用 textTheme 與既有 shared 元件，保留 Android SafeArea、返回與字體縮放。QR 原始影像與白色 quiet zone 是掃描用途的例外。

## 驗證

`mobile/tool/verify.sh` 執行資料同步、工具版本、DOM fixtures、格式、分析與 Flutter 測試。自動化測試使用合成資料，不送出實際校務操作。

- [在學證明裝置驗收](registration-device-checks.md)
- `mobile/integration_test/`：Android 原生橋接、WebView 與 UI 測試。
- `calendar-data/`：校曆原始 JSON、Schema 與離線驗證。

Flutter 所帶 AGP 9 模板與目前 InAppWebView 的舊 ProGuard 設定不相容，故固定 AGP 8.11.1／Gradle 8.14.3／Kotlin 2.2.20。升級時需一起驗證原生套件；建置仍會出現 Flutter 未來支援提醒。

實際校方登入、門禁、點名、報名與文件儲存需要帳號及裝置驗收；fixture 通過不代表已完成端到端驗證。
