# NIU 跨平台 Design System 對齊 0.5.2

## Audit先行

2026-09-29以git ls-remote核對GitHub HEAD `96e8cdf3a4738ed31420f3de748fbee862906406`，與本機Swift參考一致。實際閱讀Theme.swift、NIUComponents.swift、MinimalCard.swift、HomeView.swift、RootView.swift、NIUTabNavigationView.swift及Flutter shared/app/feature UI。完整盤點見`design-system-cross-platform-audit.md`。

Swift採system semantic顏色、4/8/12/16/24/32/48 spacing、6/10/14/18/24/32/pill圓角，卡片通常18、首頁特徵卡更大。NIUIconButton視覺44圓形accentSoft；NIUChip與StatusBadge分別表達資訊與狀態，SectionHeader20bold。動畫spring response250/350/500ms不是必須照搬Android物理曲線。舊MinimalCard存在hard-coded black，不複製其深色缺陷。

## Mapping

| Swift | Flutter |
| --- | --- |
| system/grouped background | NiuColors.background／groupedBackground |
| secondary/tertiary surfaces | surfaceSecondary／surfaceTertiary，保留surface/elevated alias |
| label/secondary/tertiary | label／secondaryLabel／tertiaryLabel |
| fills | fill／secondaryFill／tertiaryFill |
| accent opacity12%/25% | accentSoft／accentMedium |
| system status | success／warning／error／info |
| 4–48 spacing | xs/sm/md/lg/xxl/xxxl/x4l，semantic content/section/large/spacious |
| existing Android gutter20 | page token，作為明確平台例外保留 |
| radius6–32 | xsmall/small/medium/large/xlarge/xxlarge，card24/hero32/control14 |
| largeTitle→caption | ThemeData.textTheme existing role mapping，不引入SF字型 |
| fast/standard/slow | NiuMotion250/350/500 + reduced-motion helper |

## Common components

保留AppCard/HeroCard/IosPageHeader等既有名稱；NiuCard相容層不重建。
新增NiuFeatureCard、NiuInfoChip、NiuStatusChip、NiuFilterChip，語意icons由NiuIcons管理。Status五種tone都帶文字及icon；Filter保持selected/disabled及至少48dp，資訊chip本身不假裝按鈕。
圓形控制改accent／accentSoft；低對比border與surface hierarchy取代shadow，未新增glass或glow。

## Android 行為

保留go_router/Shell與detail root Navigator、不改route與Back callbacks。Android轉場使用Flutter PredictiveBackPageTransitionsBuilder，iOS保留Cupertino transition；沒有改CupertinoApp或建立iOS project。實際手勢支援仍依OS/Flutter/既有PopScope條件。
status/navigation bar、SafeArea及IME沿用原機制。QR白底純圖是功能例外不改。

## 未來公車重用

AppCard＋SectionHeader＋NiuInfoChip（站牌／業者）＋NiuStatusChip（進站、未發車、stale等文字，tone由domain映射）＋NiuFilterChip＋RelativeUpdateText＋AppLoadingState／AppErrorState。
沒有新增公車UI、假路線或API；既有bus Phase1 domain不變。

## 邊界與尚存差異

- 不改頁面資訊架構、authentication、parser、API、cache／storage key。
- Semantic icons採現有Android Material outline映射，尚存Cupertino icon不一口氣替換，避免大規模視覺變動。
- 特殊時間軸線寬、QR quiet zone、grid cell和平台48dp控制保留功能尺寸，不能全部當spacing。
- 第三方校方網頁維持自己樣式。
- 現有Header在窄寬度長標題時有scaleDown折衷，完整Semantics保留；不是完全動態高度header。

驗證與建置結果完成後補記。

## 最終驗證

- `dart format .`完成；`flutter analyze`無問題；完整199項測試通過。
- `flutter build apk --debug`成功，簽署／SDK／64-bit ELF對齊檢查通過。
- Android16覆蓋安裝與啟動成功，首頁淺色實際截圖檢視通過。切換深淺色時模擬器System UI曾無回應，關閉系統提示後恢復；不宣稱所有裝置手勢／畫面已完整真機驗證。
- 深淺色／放大字體的主要頁面由既有widget回歸及新增chip token tests覆蓋。
- 下載`http://<preview-server>:8080/NIU-Life-0.5.2-preview.apk`，HTTP200。
- 保留既有Gradle／AGP／Kotlin未來支援提醒，不做無關工具鏈升級。

## 收斂量測

全Flutter lib現有153處NiuSpacing、11處NiuRadius引用。literal radius由29降到18；保留的特殊幾何與未納入此輪的次要頁面屬已記錄差異，不宣稱所有magic number已清除。
目前10個主要feature presentation檔完成token替換；首頁另改用NiuFeatureCard避免重複卡片實作。

## 刻意不修改

- 原始Swift、App API contract、所有Repository／解析模型／認證／快取格式與storage keys。
- 課表逐節顯示、Moodle分頁、畢業邏輯、校曆資料及QR image bytes。
- 註冊PDF原生操作、通知／Widget native流程；此次只針對Flutter樣式。
- 較舊次要控制中的特定尺寸保留，避免沒有功能理由的大量替換。
