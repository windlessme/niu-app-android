# Visual parity audit — 2026-09-30

Evidence: actual SwiftUI sources in qian403/NIU-app, not iOS screenshots. Android
values below are measured from widget configuration before this change. Dynamic
card heights depend on content and text scale, not a fixed cross-platform number.

## Mismatch matrix

Columns cover top/header, gutters/sections, card geometry/composition, typography,
metadata/icons, actions/tabs and density. Heights not explicitly set are intrinsic.

| Screen | iOS implementation | Flutter mismatch / action |
|---|---|---|
| Home | HomeView: top16/gutter24/sections24; greeting32; service titles16/meta12, icon24 in56; cards radius18 | gutter20 retained; card titles19/meta14 inflate rows; large gradient scanner competes with greeting; reduce text and scanner fill |
| Schedule | ClassScheduleView: native inline header; top12/gutter20; cards padding16/radius18; course16/time11, gap12 | custom header76/title26 plus explicit76 host; card typography19/meta14; reduce header and text, retain period layout |
| Moodle | MoodleView: gutter16/top12; card padding16/radius18, title16/meta12; icon17 in40 | card padding20/radius24/title19; metadata split into tall rows; use content16 and stronger type separation |
| Course Detail | MoodleCourseDetailView: summary title16/meta11; tabs icon15 above label11, gap4, minimum52/radius16 | horizontal icon24 + label16 creates chip-like wide tabs; change shared tab composition, preserve scrolling and visited-state |
| Attendance | AttendanceRecordViews: gutter16/top8/bottom28; ledger hierarchy and selectable sections | Android keeps all ledgers and scan CTA by established architecture; title19 and body16 too similar to status/meta; benefit from typography, no ledger-selection rewrite |
| Graduation | GraduationThresholdView: top16/gutter24/sections24, single hero metric56; rows14/meta13, card padding16–24 | Android intentionally count-based hero, title19 rows and long metadata; tighten shared type but preserve meaning/counts |
| Calendar | AcademicCalendarView: gutter20/top12/bottom28, sections24; native header; caption weekdays, compact controls | geometry already close; custom76 header and 26 title consume space; shared header change, do not shrink day touch targets |
| Library | LibraryCodeView: gutter24/sections24; square white code, inline header; caption refresh | Flutter gutter20 with correct square footprint; oversized custom header; retain QR dimensions/quiet zone |
| Student leave | No corresponding SwiftUI leave screen found in inspected repository | no direct parity claim; use same inline header, metadata and card family; preserve two-column dashboard and all record semantics |
| Campus services | iOS Home feature grid, no equivalent four-tab campus screen | Android root IA is established; keep grid/root destinations, reduce shared title weight and icon competition |

## Top five systemic differences

1. **Header chrome**: custom toolbar76/title26/leading70 vs iOS inline navigation;
   the fixed76 schedule wrapper duplicates the excessive vertical footprint.
2. **Text role collision**: Flutter card19 and body16/meta14; SwiftUI course16,
   metadata11–12. Default Material tracking and 1.4 body height amplify density.
3. **Tabs composition**: Flutter horizontal icon+body text instead of compact
   vertical icon/caption; same soft fill alone did not fix proportion.
4. **Card content geometry**: Moodle20 padding plus separate teacher/credit rows
   vs iOS16 with compact secondary rows; radius alone cannot correct height.
5. **Accent area**: Home gradient scan panel plus greeting/cards/icons dominates;
   iOS scanner is a neutral row with accent confined to the icon container.

## Convergence rules

Inline navigation17 semibold, page title28 bold, hero metric34+, section20 semibold,
card17 semibold, body16 regular at1.35, secondary13 at1.3, metadata12 at1.3,
caption11 at1.25. Explicit zero tracking for CJK. Android actions remain >=48dp.
Toolbar64, icon20 (visual) within48 target. Tabs icon18/caption12, intrinsic height
with a48 minimum; no fixed text height. Card gutters remain the established20.

## Review limitations

iOS library and attendance sources are outside Features/*/Views and were read
directly. No iOS leave/campus equivalent or iOS rendered screenshots were available.
Do not describe source inference as pixel-perfect comparison. Android screenshots
and automated responsive fixtures supplement the source audit; physical camera,
school authentication and full live data states remain separate acceptance work.
