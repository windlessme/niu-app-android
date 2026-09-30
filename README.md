# NIU-Life Android

國立宜蘭大學非官方校園工具，使用 **Flutter / Dart** 開發，主要執行於 Android。

本專案以 [qian403/NIU-app](https://github.com/qian403/NIU-app) 的 iOS 開源實作、功能與 Design System 為參考，採獨立 Android repository 維護。與國立宜蘭大學並無隸屬、合作或授權關係；校務資訊及操作結果以學校系統為準。

## 維護文件

- [架構與維護](docs/android-flutter-architecture.md)
- [Android 隱私政策](docs/android-privacy-policy.md)
- [校務登入頁來源與測試](docs/sso-login-capture-findings.md)
- [在學證明裝置驗收](docs/registration-device-checks.md)

## 功能

- 課表與離線快取、逐節顯示、桌面小工具、提醒與行事曆匯出。
- M 園區課程、公告、教材、作業、討論、成績與出席紀錄。
- QR Code 點名、圖書館門禁／借書圖碼。
- 學年度行事曆、歷年成績、畢業門檻、活動報名。
- 註冊資訊與本人在學證明 PDF。
- 裝置加密登入憑證、自動記住帳密、深淺色與無障礙版面。

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

保留 `mobile/` 路徑以相容既有 CI 與工具。校曆與致謝目前仍從原專案公開 GitHub JSON 來源更新；不是此repository提供私人校務後端。
Android applicationId 目前為開發識別碼 `dev.niulife.prototype.niu_mobile`；正式Play發行前確認永久識別碼與簽署設定。

## 授權與致謝

原始專案為 **MIT License，Copyright (c) 2026 CHIEN**，完整聲明保留於 [LICENSE](LICENSE) 與 App 授權頁。另見 [NOTICE.md](NOTICE.md)。

感謝 [qian403/NIU-app](https://github.com/qian403/NIU-app) 與 [KennyYang0726/NIU_APP_IOS](https://github.com/KennyYang0726/NIU_APP_IOS) 提供參考。
