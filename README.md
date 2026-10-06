# NIU-Life Android

[![Android CI](https://github.com/windlessme/niu-app-android/actions/workflows/android.yml/badge.svg)](https://github.com/windlessme/niu-app-android/actions/workflows/android.yml)
[![Google Play](https://img.shields.io/badge/Google_Play-NIU--Life-414141?logo=googleplay)](https://play.google.com/store/apps/details?id=me.windless.niulife)

國立宜蘭大學（NIU）的非官方校園 App，把課表、M 園區、校園信箱、成績、請假與圖書館等常用校務功能整合在一個 App 裡。以 Flutter / Dart 開發，原生功能（小工具、提醒、通知）使用 Kotlin。

> [!NOTE]
> 本專案與國立宜蘭大學沒有隸屬、合作或授權關係。校務資訊及操作結果一律以學校系統為準。

NIU-Life 有 Android 與 iOS 兩個版本，功能與設計保持一致：

| 平台 | 維護者 | Repository |
| --- | --- | --- |
| Android | [Windless](https://github.com/windlessme) | [windlessme/niu-app-android](https://github.com/windlessme/niu-app-android)（本 repo） |
| iOS | [Qian](https://github.com/qian403) | [qian403/NIU-app](https://github.com/qian403/NIU-app) |

## 下載

正式版已上架 [Google Play](https://play.google.com/store/apps/details?id=me.windless.niulife)。多數功能需要有效的宜蘭大學帳號。

## 功能

| 類別 | 內容 |
| --- | --- |
| 課表 | 離線快取、上課提醒、上課中通知、行事曆匯出；桌面小工具（快捷列、下一堂課、今日課表）與 App 捷徑 |
| M 園區 | 課程、公告、教材、作業、討論、成績、出席紀錄、即將截止；QR Code 快速點名 |
| 校園信箱 | 收信、寫信、回覆／轉寄、附件、搜尋，驗證碼自動辨識 |
| 學業 | 期中／學期／歷年成績、畢業門檻、請假查詢與申請、活動報名 |
| 圖書館 | 入館碼、借書條碼、空間與設備預約 |
| 其他 | 註冊資訊與在學證明 PDF、郵件包裹查詢、學年度行事曆、作業死線與重要日期通知 |
| 帳號與介面 | 登入憑證以裝置加密保存、自動記住帳密、示範模式、深淺色與無障礙版面 |

## 開始開發

### 環境需求

工具鏈版本以 [`mobile/toolchain.json`](mobile/toolchain.json) 為準：

- Flutter 3.47.5 / Dart 3.13.4
- Java 17
- Android SDK（API 36）
- Python 3（校曆資料同步與檢查）
- Node.js（校方網頁 DOM fixtures 測試）

### 建置與驗證

```sh
cd mobile
flutter pub get --enforce-lockfile
python3 tool/sync_calendar.py --check   # 確認 App 內建校曆與 calendar-data/ 一致
bash tool/verify.sh                     # 格式、靜態分析、架構檢查、DOM fixtures 與測試
flutter build apk --debug
```

`verify.sh` 與 CI（[`.github/workflows/android.yml`](.github/workflows/android.yml)）執行相同檢查。自動化測試只使用合成資料，不會連線學校系統。更多細節見 [`mobile/README.md`](mobile/README.md)。

### 示範模式

沒有學校帳號也能用示範模式瀏覽完整介面。以帳號 `niulifedemo` 登入即進入示範模式：資料全部來自 [`mobile/lib/core/demo/demo_data.dart`](mobile/lib/core/demo/demo_data.dart)，請假、活動報名、點名、作業等送出動作皆為模擬。密碼不放在 repo 中，App 只保存其 SHA-256。

## 專案結構

```text
mobile/                Flutter App、Android 原生端、測試與開發工具
calendar-data/         公開學年度行事曆資料、schema 與驗證腳本
app-content/           App 從 GitHub 讀取的公開內容（致謝名單、公告）
docs/                  架構、設計與資料研究文件
.github/workflows/     Android CI
```

App 不依賴任何私人後端：校務功能直接連線學校系統，公開內容（`app-content/`、校曆）則透過 GitHub Raw 讀取。Android applicationId 為 `me.windless.niulife`。

## 文件

- [架構與維護](docs/android-flutter-architecture.md)
- [校務登入頁來源與測試](docs/sso-login-capture-findings.md)
- [在學證明裝置驗收](docs/registration-device-checks.md)
- [校曆資料格式與更新流程](calendar-data/README.md)
- [交接紀錄](HANDOFF.md)、[歷史紀錄](docs/archive/README.md)

## 參與貢獻

歡迎透過 issue 回報問題或提出 pull request。送出 PR 前請先在本機跑過 `bash tool/verify.sh`。

> [!WARNING]
> 請勿在 repo、issue、PR、截圖或 log 中公開學校帳密、Cookie、Token 或任何個人證明文件。需要重現校務頁面問題時，請先去除個人資料，再整理成 `mobile/test/fixtures/` 中的合成 fixture。

## 隱私與聯絡

- [隱私權政策](https://niu-life.app/privacy)：iOS 版、Android 版與網站共用（[原始檔](https://github.com/windlessme/niu-life-site/blob/main/src/content/privacy.md)）
- 聯絡信箱：[hi@niu-life.app](mailto:hi@niu-life.app)

## 授權

本專案以 [MIT License](LICENSE) 授權，同一份聲明也隨 App 內的授權頁發布。

本 repo 以 [qian403/NIU-app](https://github.com/qian403/NIU-app) 的 revision `96e8cdf` 為起點，`calendar-data/` 與 App 內建的校曆資料（`mobile/assets/academic_calendar/`）沿用自該專案，因此 LICENSE 同時保留上游的著作權聲明（Copyright (c) 2026 CHIEN）。來源細節見 [NOTICE.md](NOTICE.md)。

學校名稱、標誌與校務資料的權利屬於各自的權利人。

## 致謝

- [qian403/NIU-app](https://github.com/qian403/NIU-app)：NIU-Life iOS 版
- [KennyYang0726/NIU_APP_IOS](https://github.com/KennyYang0726/NIU_APP_IOS)
