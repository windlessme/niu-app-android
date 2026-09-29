# Light surface hierarchy 0.5.3

根因：Theme只覆寫surface與surfaceContainerHighest；M3 seed生成的surfaceContainerLow在淺色與page接近，而課表卡和星期控制共同消費它。

| token | Light | Dark | 用途 |
|---|---|---|---|
| pageBackground | #E8EDF3 | #000000 | Scaffold背景 |
| surface/cardSurface | #FFFFFF | #1C1C1E | 一般卡片與內容 |
| surfaceSecondary | #D9E2ED | #1C1C1E | 未選星期、次要控制 |
| surfaceTertiary | #CDD7E3 | #242426 | 第三層控制／輸入底 |
| navigationSurface | #FFFFFF | #1C1C1E | 底部導覽 |
| accentSoft/infoSoft | #DBEAFF | 原accent12% | toolbar與資訊chip |
| separator | 原#D9D9DF | 原#38383A | 細分隔線 |

ColorScheme全部container層補齊mapping，不依賴Material自動生成近白值。AppCard指定cardSurface、課表未選日期surfaceSecondary、課程cardSurface、節次infoSoft、bottom nav navigationSurface。
其餘首頁、Moodle、課程詳情、校曆、畢業、圖書館外框與校園由全域Card／Scaffold／bottomSheet／input theme同步套用。
不新增粗框／陰影；QR純白掃描區是功能例外仍保留。Theme與status bar的brightness判斷保留於映射層，未把模式判斷塞進Schedule。

驗證結果於發布補記。

全套201項測試通過；segment mapping最終調整後16項相關回歸通過；全專案分析無問題。
Android16合成課表實際截圖測試與flutter drive通過，檢視 `/tmp/opencode/niu-surface-review/surface-light.png`、`surface-dark.png`：淺色白卡／灰藍control清楚，深色維持黑底深灰。
最終debug APK成功、簽署通過並發布0.5.3。未變更資料／版面／登入邏輯。
