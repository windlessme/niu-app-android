# Android Visual Design System audit

## Baseline and scope

Audit of `mobile/lib` before this refactor (2026-09-30). Existing route, authentication,
data and cache behavior remains authoritative. No backend or navigation migration.

### Screen inventory

| Family | Screens / surfaces | Existing inconsistencies |
|---|---|---|
| App | root shell, auth gate, school WebView, login | mixed native toolbar vs custom header, isolated spinners |
| Home | profile, today's classes, service shortcuts | hand-built section header, literal gutters/radii, competing blue icons |
| Schedule | timetable, options sheet, export | per-page controls/radii; retain timetable geometry |
| Moodle | course list/detail, announcements, resources, assignments, forum, grades, web/file viewer | bespoke tabs, solid selected fill, mixed cards/loading states |
| Attendance | scanner, record sections | scanner contrast is a functional exception; record cards already shared |
| Calendar | academic calendar, event sheet | repeated padding/radii; category colors are semantic, not decoration |
| Grades | term selector, grade rows, statistics | five locally shaped cards |
| Graduation | cached dashboard, filters, detail expansion | hero + colored status indicators; preserve requirements semantics |
| Events | list, sync, detail, school action | shared states but scattered literal spacing |
| Library | code, mode selector, loading/error | QR white quiet zone must remain; literal gutters |
| Registration | certificate actions, registration rows | local spacing, paired primary/secondary actions |
| Leave | dashboard, records, native details, workflow | shared cards but ad-hoc empty/error text and toolbar actions |
| Settings | appearance, about/license, credits/privacy | mixed toolbar and metadata font overrides |

### Pattern inventory

Baseline textual call-site inventory: 36 card constructors; 85 button constructors;
9 chip constructors; 13 section headers; 12 tab/segmented references; 34 state/spinner
constructors; 2 modal sheets; 31 toolbar references. These are call sites, not unique
runtime widgets. Root navigation is the four-destination custom shell.

Literal styling inventory: 57 numeric EdgeInsets calls, 17 numeric circular radii,
21 numeric font sizes (16 are the central theme), 13 opacity expressions, 7 border
expressions, 6 millisecond durations. No BoxShadow constructor was found. Color grep
also finds `NiuColors` references: inspect actual usages rather than treating every
match as a hard-coded color. Network polling/timeout durations are NOT animation tokens.

## iOS source reviewed

- `Shared/Theme/Theme.swift`: semantic label/surface roles; 4/8/12/16/24/32 spacing;
  18/24/32 radius scale; hierarchy via body/callout/caption, not many bold labels.
- `Shared/Components/NIUComponents.swift`: primary vs soft secondary action, card
  composition. Android retains flexible height and >=48dp targets, not iOS fixed heights.
- `Features/Moodle/Views/MoodleCourseDetailView.swift`: quiet course summary and
  accent-tinted icon/label tab selection rather than a solid blue block.

## Ordered implementation

1. Tokens: explicit compact card, interaction sizing, subtle control surfaces.
2. Shared components: card tiers, neutral status surfaces, consistent states.
3. Navigation/header: centered section action alignment, quiet toolbar controls;
   preserve predictive-back and four-tab navigation.
4. Controls: central Material button/chip/tab themes and reusable scrollable tabs.
5. Data states: unify loading/error presentation while retaining actions and text.
6. Page adoption: migrate repeated visual literals to existing spacing/radius tokens,
   use the shared tabs and preserve all established information architecture.

## Rules

- Hero radius 28 / padding 24, standard 24 / 20, compact 18 / 16.
- Page gutter 20; section 24; card gap 12–16; no decorative shadows or strong borders.
- Primary buttons use accent; secondary and toolbar actions use neutral foreground.
- Selected controls use accentSoft; unselected controls use surfaceSecondary.
- Typography remains TextTheme; metadata is bodySmall/labelSmall with secondary color.
- Android touch targets >=48dp, no fixed text-bearing heights, responsive wrapping.
- QR/scanner contrast, document rendering, chart geometry and network intervals are
  intentional exceptions, not indiscriminate token substitutions.

## Validation record

Each phase runs format/analyze/full Flutter tests. Final Android APK build and
responsive light/dark tests cover existing fixtures; real-account school pages,
camera and all device-specific gesture/IME variants still require manual acceptance.

## Delivered changes and remaining coverage

All six phase checks passed, including a final full suite (240 tests). Direct page
adoption: Home shared section heading; Moodle Course Detail shared icon/label tabs;
Moodle web/attachment/auth loading and error states; Events compact fact cards.
Spacing/radius migration: Home, Library, Settings, Registration, Events, Attendance,
Login and Grades. Calendar, Schedule, Graduation and Leave inherit the shared card,
button, chip, section/header and surface changes without changing their structure.

Still present deliberately or pending further device review: timetable/barcode
geometry, scanner contrast, calendar category colors, inline progress indicators,
some locally tuned calendar/schedule labels and bottom-sheet layout literals.
Cupertino segmented controls retain their selection behavior and adopt the same
soft selected color; they are not replaced with a new navigation framework.
No claim of exhaustive pixel-level visual acceptance on every physical device.
