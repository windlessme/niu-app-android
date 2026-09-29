# UI／UX 統整 0.3.1

本次接續 0.3.0 的實際使用流程調適，保留 Flutter 與資料層。

## 全域與首頁

- 首頁區分「尚未同步」與「今天接下來沒有課程」，避免有快取卻提示重新同步。
- 首頁下拉失敗提供友善訊息，保留既有內容。
- Header 保留完整 accessibility 標題，狹窄畫面有操作按鈕時仍可辨識頁面。
- 全域深淺色轉換縮短至 200ms，降低動態效果設定時取消非必要轉換。
- 全域 loading 訊息置中並沿用 textTheme。

## 驗證

- `dart format .` 完成；`flutter analyze` 無問題；`flutter test` 141 項通過。
- `flutter build apk --debug` 成功；簽署／SDK／64-bit ELF 16KB 靜態檢查通過。
- Android 16 模擬器覆蓋安裝、啟動成功。相機與亮度原生行為仍需不同廠牌真機驗證。
- 320px、2x 字體、深淺色、300px 鍵盤 inset 已納入 supporting screens 測試。

## 功能頁

- Moodle 防止重複刷新，捕捉同步 loader 例外、保留舊資料、顯示 stale/retry；搜尋使用快取 presentation 欄位；學期撤回後清除失效選擇。
- 作業狀態更新中不保留舊提交控制，討論分頁操作可換行。
- 課表 daily presentation 快取，320px／大字體採全寬課程卡，日期 semantics 統一。
- 畢業 Dashboard 移除重複進度條，計算方式改為可展開並遵守 reduced motion。
- 校曆與來源 sheet 加 SafeArea，今天／PDF／完成操作至少48px，搜尋清除回歸通過。
- 設定外觀選項垂直布局，致謝更新失敗保留內容並提供重試。
- 圖書館 loading/error 不受條碼比例裁切，亮度操作序列化避免離頁後反而調亮。
- 點名手動輸入可捲動至鍵盤上方，focus 時停相機、重新操作清掉舊錯誤、短清單也可下拉更新。
