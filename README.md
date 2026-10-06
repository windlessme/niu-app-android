# NIU-Life Android

國立宜蘭大學非官方校園工具，使用 **Flutter / Dart** 開發，主要執行於 Android。

NIU-Life 的 Android 版由 [Windless](https://github.com/windlessme) 維護，iOS 版由 [Qian](https://github.com/qian403) 維護（[qian403/NIU-app](https://github.com/qian403/NIU-app)），兩個版本的功能與設計保持一致。與國立宜蘭大學並無隸屬、合作或授權關係；校務資訊及操作結果以學校系統為準。

## 維護文件

- [架構與維護](docs/android-flutter-architecture.md)
- [隱私權政策](https://niu-life.app/privacy)（iOS 版、Android 版與網站共用，來源在 [niu-life-site](https://github.com/windlessme/niu-life-site/blob/main/src/content/privacy.md)）
- 聯絡信箱：hi@niu-life.app
- [校務登入頁來源與測試](docs/sso-login-capture-findings.md)
- [在學證明裝置驗收](docs/registration-device-checks.md)
- [交接紀錄](HANDOFF.md)
- [歷史紀錄](docs/archive/README.md)

## 功能

- 課表與離線快取、桌面小工具（快捷列、下一堂課、今日課表）、App 捷徑、上課提醒、上課中通知與行事曆匯出。
- M 園區課程、公告、教材、作業、討論、成績與出席紀錄；QR Code 快速點名。
- 校園信箱：收信、寫信、回覆／轉寄、附件、搜尋，驗證碼自動辨識。
- 期中／學期／歷年成績、畢業門檻、請假查詢與申請、活動報名。
- 圖書館入館碼、借書條碼與空間設備預約。
- 註冊資訊與在學證明 PDF、郵件包裹查詢、學年度行事曆。
- 作業死線、重要日期與上課前通知。
- 裝置加密登入憑證、自動記住帳密、示範模式、深淺色與無障礙版面。

正式版已上架 Google Play。部分校方流程需要有效的學校帳號才能使用。

## 開發

版本與工具鏈以 [`mobile/toolchain.json`](mobile/toolchain.json) 為準：Flutter 3.47.5、Dart 3.13.4、Java 17、Android API 36。

```sh
cd mobile
flutter pub get --enforce-lockfile
python3 tool/sync_calendar.py --check
bash tool/verify.sh
flutter build apk --debug
```

Node.js 用於校方網頁 DOM fixtures。正式校務操作需自己的有效學校帳號；不要在版本庫、issue、截圖或log公開帳密、Cookie、Token或個人證明。

## 目錄

```text
mobile/                 Flutter App、Android host、測試、工具
calendar-data/          公開校曆資料與驗證工具
app-content/            公開致謝資料
docs/                   架構、設計、資料研究與開發紀錄
.github/workflows/      Android CI
```

保留 `mobile/` 路徑以相容既有 CI 與工具。校曆目前仍從原專案公開 GitHub JSON 來源更新，致謝名單從本 repository 的 `app-content/credits.json` 更新；不是此repository提供私人校務後端。
Android applicationId 為 `me.windless.niulife`（Google Play 套件名稱，發布後不可變更）。

Google Play 審查使用示範帳號 `niulifedemo`（密碼記錄於 Play 控制台「應用程式存取權」）。以此帳號登入會進入示範模式：所有資料來自 `lib/core/demo/demo_data.dart`，請假、活動報名、點名、作業等送出操作皆為模擬，不連線任何學校系統；App 內只保存密碼的 SHA-256。

## 授權與致謝

原始專案為 **MIT License，Copyright (c) 2026 CHIEN**（iOS 版），完整聲明保留於 [LICENSE](LICENSE) 與 App 授權頁。另見 [NOTICE.md](NOTICE.md)。

感謝 [KennyYang0726/NIU_APP_IOS](https://github.com/KennyYang0726/NIU_APP_IOS) 提供參考。
