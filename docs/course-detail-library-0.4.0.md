# 0.4.0 課程詳情與圖書館

## 範圍

沿用現有 NiuColors／NiuTheme、AppCard、IosPageHeader、CircleIconButton、Empty／Loading／Error 元件。
課表只恢復逐節顯示；M 園區根列表、畢業門檻、校曆及底部導覽外觀不重做。

## 課表

scheduleLessons 預設不合併，第三／第四節各顯示一張既有樣式的卡片。
原始資料、快取與匯出服務不變；節次前後綴正規化仍保留。

## 導覽

Moodle 的 pushMoodle 使用 root Navigator，課程／教材／作業等詳情覆蓋 ShellRoute，隱藏 root bottom navigation。返回仍回到原本 M 園區列表與狀態。
圖書館原本已是 Shell 外的 go_router route，延續該層級。

細節實作與驗證完成後補記。

## 課程詳情

- 六分頁水平捲動、selected pill 與灰色未選項，lazy IndexedStack 保留已開分頁與捲動位置，非選取分頁停止 ticker。
- 教材週次作為 section heading，資源以 CourseResourceTile 精簡呈現；日期區間由共用 presentation formatter 處理。
- 公告作者／日期／摘要與附件，作業截止排序及真實 submission 狀態，討論回覆數，成績未知顯示尚未公布。
- Course Hero 分開中文／英文／代碼／教師／學分；說明按標籤分節、移除重複 metadata，不可靠的原文仍保留。
- 新增 `course_detail_presentation.dart`、`course_detail_widgets.dart`，沿用現有元件。
- Course Hero 與文字 sections 分開，不再用單一巨卡包全部資訊；明確標籤的分號串接資料切成段落，已知重複metadata去除。若校方提供email可開啟mailto。
- 課程資源專用 `course_resource_tile.dart` 僅顯示實際mimetype／filesize，沒有資料就不造出標籤。

## 本次限制

- 校方只回傳一般敘述的成績計算，保留分節文字，不猜測比例或產生虛構評分項目。
- 作業state由現有submission API取得；失敗保持未知，不以截止時間假定已提交／未提交。
- API不提供點名紀錄且網站Cookie失效時，仍需要校方網頁完成驗證；不能將API備援修正視為所有真實課程已驗收。

## 圖書館

- 共用 `AppSegmentedControl` 與校曆一致，Header 不重做。
- 白底 QR max420、等比例 quiet zone；條碼2.2比例，未更動原始影像或新增個資。
- 更新按鈕48px、單一進行中請求，換帳號／類型只採最新結果；最後更新24h台北時間。
- 失敗只保留同帳號／類型／當日／未滿5分鐘的舊圖；跨午夜或逾期清除。
- RouteObserver 偵測遮蓋頁面，暫停timer／請求與亮度；恢復後重新驗證。新增 `clock_format.dart`。

## 已驗證

- 全專案 `flutter analyze` 無問題；`flutter test` 166項通過。
- `dart format .` 完成，Android debug APK建置／簽署／SDK及ELF靜態檢查通過，Android16模擬器覆蓋安裝與冷啟動成功。
- 下載：`http://<preview-server>:8080/NIU-Life-0.4.0-preview.apk`。
- 課表逐節顯示／中文節次／字體放大相關10項測試通過。
- root Navigator 詳情頁測試通過：進入後無 bottom navigation，返回恢復原列表與頁籤。

## 點名冊

- 將未接線的 HTML fallback 接回 API 失敗、instance lookup 失敗與全 pending 情境。
- 只讀課程自己的 attendance view=5，以 WebView Cookie 登入，不送點名、REST token 或跨課程查詢。
- 出席／遲到／缺席／請假／尚未記錄分開呈現；API 有效 pending 回應在網頁失敗時保留。
- 自動網頁登入 key 不可用時仍開啟已驗證的校方網址，允許使用者完成網站驗證後返回重試。
- 24項出席／wire測試通過，真實課程紀錄仍需有效帳號確認。

## 修改檔案

```text
mobile/lib/features/schedule/schedule_presentation.dart
mobile/lib/features/moodle/{moodle_screen,moodle_web_screen,course_widgets,course_detail_presentation,course_detail_widgets,course_resource_tile}.dart
mobile/lib/features/attendance/{attendance_repository,attendance_screen}.dart
mobile/lib/features/library/library_screen.dart
mobile/lib/shared/{app_segmented_control,clock_format,shared}.dart
mobile/lib/app/app.dart
mobile/lib/features/academic_calendar/calendar_screen.dart（只替換同樣外觀的共用segment）
mobile/pubspec.yaml
mobile/test/{attendance_records,course_detail,library_screen,detail_navigation,schedule_presentation,schedule_period_label,schedule_view,secondary_screens_accessibility,moodle_wire}_test.dart
mobile/test/features/course_presentation_test.dart
mobile/integration_test/ui_redesign_test.dart
```
