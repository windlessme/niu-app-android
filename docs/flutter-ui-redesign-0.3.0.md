# Flutter UI 重構 0.3.0

## 架構盤點

- Flutter 3.47.5／Dart 3.13.4，Android minSdk 26／targetSdk 36。
- Material 3 作為 Flutter 組件基礎；Cupertino 圖示、分段控制與輕量轉場。
- go_router ShellRoute 維持首頁／課表／M 園區／校園；詳情沿用 Navigator push。
- Riverpod 負責校曆 Repository 注入與非同步資料；CampusSession ChangeNotifier 管理帳號，頁面使用 StatefulWidget 呈現局部狀態。
- Dio／Repository／Service／WebView 擷取與原始 model 保留。這次只新增 presentation transformation，不更換 API、登入流程、快取或狀態管理框架。
- 對應頁面：`features/schedule/schedule_screen.dart`、`features/moodle/moodle_screen.dart`、`features/academic_calendar/calendar_screen.dart`、`features/graduation/graduation_screen.dart`。

## Design System

- `shared/niu_colors.dart`：semantic ThemeExtension、spacing 4/8/12/16/20/24/32、一般卡24／hero28／control18。
- `shared/niu_theme.dart`：完整 Light／Dark 色彩、textTheme、Android system bars、關閉 ripple、Cupertino 轉場。
- `shared/ios_page_header.dart`：置中 Header、50px 圓形控制、返回使用 Navigator／go_router。
- `shared/app_cards.dart`：AppCard、HeroCard、SectionHeader。
- `shared/app_search_field.dart`：正常 layout flow 的搜尋框、清除、語意標籤。
- `shared/app_states.dart`：Loading／Error。
- `shared/relative_update_text.dart`：台北民用日期的剛剛／分鐘前／今天／昨天／天前更新。
- 相容出口 `shared/shared.dart` 保留 NiuCard／NiuEmptyState 等既有使用方式。

## 主要頁面

### 課表

- 保留快取優先與手動更新；移除帳號與微秒 timestamp。
- 獨立 `schedule_presentation.dart` 合併同名／教師／教室／曜日且節次連續的課程。
- 七日選擇器、課程標記、時間範圍與時間軸卡片；更新時間人類可讀。
- 匯出、學期設定、Widget／提醒放入 Header 操作面板。

### M 園區

- `course_presentation.dart` 與 `course_widgets.dart` 區分列表摘要與完整細節。
- 課程 Hero、學期 capsule、搜尋、lazy cards；列表不呈現長篇 syllabus。
- 詳情保留課程原文與校方提供欄位；未提供教師／學分不猜測。
- 下拉更新保留現有資料，失敗顯示 stale／retry；使用者刷新成功才輕觸回饋。

### 畢業門檻

- `graduation_presentation.dart` 區分 available／unknown／notTested／passed／failed。
- Dashboard 已知門檻進度、單張時數卡、能力資格、學分與學程。
- 學分按已修／應修（3／128）及浮點比例顯示；缺資料不填零。
- 非計入時數不加入進度；總進度是已知可比較門檻的等權平均，明示不是校方畢業資格判定。

### 校曆

- Header、今天 capsule、月曆／事件 segments、學年度、分類、月份層級。
- 七等寬欄，窄螢幕可水平捲動日期區以維持48px目標，最多3個實心／空心 marker，再用額外數量提示。
- 選日顯示當日與期間事件數、事件 accent；搜尋正常參與捲動，不使用浮層遮擋。
- 日期事件 index 在 provider presentation 層預先建立；revision 移到來源詳情。

## 其他同步調整

- supporting screens（登入、點名、圖書館、成績、活動、附件、校方 WebView）統一 Header 與基本間距。
- bottom navigation 保留四頁籤，66px 最低高度＋實際 SafeArea；大字體可自然增高。
- 首頁配色／卡片與文字沿用 Theme，窄螢幕或大字體服務卡改單欄。
- 設定→特別感謝永久加入 https://github.com/qian403/niu-app，遠端致謝更新不會覆蓋此入口。

## 資料限制

- 課表原始資料沒有穩定 course ID 或每日 occurrence date，因此以課名＋教師＋教室＋曜日＋連續節次合併，不修改原始 model。
- Moodle 若沒有明確的中文／英文名稱、職稱或學分欄位，僅使用明確標記資訊；未知顯示未提供。
- 校方原始網頁（驗證碼、報名表單等）保留自身樣式，Flutter 不強制改寫第三方網站 UI。
- 總畢業進度屬已知資料估算；缺漏與不明判定明確揭露。

## 驗證

- Widget tests 覆蓋 Light／Dark、320／600px、1x／2x 文字，連續節次、未知資格、比例與校曆 marker。
- `flutter analyze`、`flutter test`、`dart format .`、Android build 與模擬器結果於發布時補記。
- Android 16 實際執行 UI 整合測試通過：深／淺色的合併課表、畢業 Dashboard、Moodle 卡片；使用合成資料，不需校務登入。
- 全套測試曾因舊測試尋找 Material BackButton 失敗，已改成共用 Header 的「返回」語意控制，並驗證返回行為。
- 最終驗證：`dart format .` 完成；`flutter analyze` 無問題；完整 `flutter test` 131 項通過，最後 Moodle loading state 調整後追加相關 3 項測試通過。
- `flutter build apk --debug` 成功；APK 簽署／minSdk26／targetSdk36／native ELF 16KB 靜態檢查通過。
- Android 16 模擬器安裝、冷啟動成功，實際深色首頁截圖已檢視；四頁 presentation 深／淺與放大字體另有合成資料測試。
- 下載：`http://<preview-server>:8080/NIU-Life-0.3.0-preview.apk`，HTTP 200。
- 原有 Gradle／AGP／Kotlin 未來支援提醒仍存在，未為 UI 重構更換工具鏈。

## 修改檔案清單（UI 範圍）

```text
mobile/lib/shared/{niu_colors,niu_theme,shared,niu_widgets,ios_page_header,app_cards,app_states,app_search_field,relative_update_text}.dart
mobile/lib/app/{app,campus_shell}.dart
mobile/lib/core/web/{academic_portal_screen,web_session_host}.dart
mobile/lib/features/home/home_screen.dart
mobile/lib/features/schedule/{schedule_screen,schedule_presentation}.dart
mobile/lib/features/moodle/{moodle_screen,course_presentation,course_widgets,moodle_web_screen,moodle_attachment_screen}.dart
mobile/lib/features/graduation/{graduation_screen,graduation_dashboard,graduation_presentation}.dart
mobile/lib/features/academic_calendar/calendar_screen.dart
mobile/lib/features/settings/settings_screen.dart
mobile/lib/features/authentication/login_screen.dart
mobile/lib/features/attendance/attendance_screen.dart
mobile/lib/features/library/library_screen.dart
mobile/lib/features/events/events_screen.dart
mobile/lib/features/grades/grades_screen.dart
mobile/pubspec.yaml
mobile/test/{app_navigation,calendar_design,relative_update,navigation_accessibility,schedule_presentation,schedule_screen,schedule_view}_test.dart
mobile/test/features/{course_presentation,graduation_dashboard}_test.dart
mobile/integration_test/ui_redesign_test.dart
docs/{flutter-ui-redesign-0.3.0,android-development-progress}.md
```
