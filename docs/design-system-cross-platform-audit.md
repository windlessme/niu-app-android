# Cross-platform design-system audit

## Baseline and scope

- Audit-only snapshot: local Swift HEAD `96e8cdf`. Remote HEAD equality was supplied by the requesting session; this audit independently checked local HEAD only.
- Read all of `Shared/Theme/Theme.swift`, `Features/Home/Views/HomeView.swift`, all six `Shared/Components/*.swift` files (including the full remainder of `NIUComponents.swift`), `Shared/Navigation/NIUTabNavigationView.swift`, both `App/*.swift` files, and `Shared/Extensions/View+Extensions.swift`.
- Read all Flutter `mobile/lib/shared/*.dart` and `mobile/lib/app/*.dart`, plus the complete Flutter home and Moodle course-widget sources. Searched actual feature call sites for shared components, spacing, radius, typography, colors, and motion. Feature-wide inventories below are source searches, not a claim that every feature implementation received a full behavioral review.
- `mobile/` and numerous existing documentation files were untracked at inspection. They are part of the observed working-tree baseline, not necessarily the contents of Swift commit `96e8cdf`.
- Deliverable: this document only. Functional data, services, authentication, repositories, caching, navigation, and program sources were not changed. No builds, device screenshots, or runtime visual validation were performed.

## Summary

Swift has a complete named scale, but its screens frequently use fixed fonts and direct semantic colors. Flutter has a semantic light/dark palette and shared presentation widgets, but its spacing scale differs from Swift and its radius constants are unused. Matching names alone would silently change values. Adopt a shared role/value contract first, then migrate call sites with explicit decisions for off-scale values.

The active Swift navigation baseline is **`RootView → HomeView`**, not `NIUTabNavigationView`. Flutter actively uses a four-destination `CampusShell`. Navigation parity is a separate product decision, not a token replacement.

## 1. Spacing: exact mapping

Source: `Shared/Theme/Theme.swift:76–85`; `mobile/lib/shared/niu_colors.dart`, `NiuSpacing`.

| Swift token | Swift pt | Existing Flutter equivalent (logical px) | Alignment recommendation |
|---|---:|---|---|
| `xxsmall` | 4 | `xs = 4` | Shared value 4 |
| `xsmall` | 8 | `sm = 8` | Shared value 8 |
| `small` | 12 | `md = 12` | Shared value 12 |
| `medium` | 16 | `lg = 16` | Shared value 16 |
| `large` | 24 | `xxl = 24` | Shared value 24 |
| `xlarge` | 32 | `xxxl = 32` | Shared value 32 |
| `xxlarge` | 48 | Missing | Add shared value 48 in a future implementation |
| No token | 20 | `xl = 20` | Explicitly decide whether this remains an additional spacing role |

Do not rename Flutter `xl` to Swift `xlarge`: that would conflate 20 with 32. Swift home uses outer horizontal 24, top 16, section separation 24, grid separation 16; Flutter home uses outer 20, header gap 30, section gaps including 24/16/26/14, and grid separation 16 (`home_screen.dart:63–120,227–305`). Flutter attendance padding is 22; `_HomeCard` padding is 18. These need role-level decisions rather than rounding every literal to a multiple of four.

Both implementations also contain legitimate micro-layout values: Swift course rows use gaps 3/6, chip padding 10×6 and compact badge padding 6×2; Flutter has similar 5/6/10 values. Keep dimensions, strokes, and optical adjustments distinct from layout spacing.

## 2. Corner radius: exact mapping

Source: `Theme.swift:87–96`; Flutter `NiuRadius`, `app_cards.dart`, `niu_theme.dart`.

| Swift token | Value | Flutter today |
|---|---:|---|
| `xsmall` | 6 | No named equivalent |
| `small` | 10 | No named equivalent |
| `medium` | 14 | No named equivalent; schedule controls use literal 14 |
| `large` | 18 | `control = 18`; theme input and search focus border also hardcode 18 |
| `xlarge` | 24 | `card = 24`; `AppCard` and Material card theme hardcode 24 |
| `xxlarge` | 32 | No named equivalent |
| `pill` | 999 | No named equivalent; choose a stadium/capsule shape for actual pill semantics |
| No token | 28 | `hero = 28`; `HeroCard` and home attendance hardcode 28 |

Swift card defaults are **18**, not 24: `NIUCard`, `NIUGlassCard`, `cardBackground`, and home `FeatureCard`. Swift field radius is **14**, not Flutter's 18. A proposed Swift-aligned role mapping is card→18, input→14, hero→24 or 32 after visual review, pill→capsule/stadium. This is a proposed visual change, not a description of current parity. Swift continuous corners and Flutter circular corners are not identical rendered shapes.

## 3. Typography

Swift typography helpers return styled **views**, not reusable `Font` values. They use semantic system styles and support Dynamic Type. The nominal sizes below are standard default-category iOS reference sizes, not fixed values specified in `Theme.swift`.

| Swift helper | Style / weight | Nominal pt | Flutter current nearest role / explicit size | Gap |
|---|---|---:|---|---|
| `largeTitle` | largeTitle bold | 34 | displayLarge / headlineLarge 34 w700 | Nominal size match |
| `title` | title bold | 28 | headlineMedium / headlineSmall 26 w700 | 2 smaller |
| `title2` | title2 semibold | 22 | titleLarge 21 w700 | Size and weight differ |
| `title3` | title3 semibold | 20 | titleMedium 19 w600 | 1 smaller |
| `heading` | headline (default semibold) | 17 | titleSmall 16 w600 | 1 smaller |
| `body` | body regular | 17 | bodyLarge / bodyMedium 16 | 1 smaller; Flutter height 1.4 |
| `callout` | callout regular | 16 | bodyLarge / bodyMedium 16 | Size match, different semantic role |
| `subheadline` | subheadline regular, secondary | 15 | bodySmall 14, secondary | 1 smaller; Flutter height 1.4 |
| `caption` | caption regular, secondary | 12 | labelMedium 12, secondary | Nominal size/color-role match |
| `caption2`, legacy `small` | caption2 regular, tertiary | 11 | labelSmall 12, tertiary | 1 larger |

Flutter additionally defines displayMedium 48 w700, displaySmall 40 w700, and labelLarge 16 w600. There are no exact Swift helper counterparts. Swift `AcademicRefreshFooter` uses `.footnote` (nominal 13), which also has no Theme helper. Flutter font family is not explicitly set; equal point/logical-pixel sizes do not guarantee identical font metrics or CJK line breaks. Its omitted style properties can inherit framework text-theme defaults.

Home deliberately diverges from the Swift helpers: greeting 15 medium, name 32 bold, section heading 20 bold, feature title 16 semibold, subtitle 12, header name 14 semibold and university 11. Flutter uses greeting titleMedium 19 semibold, name headlineLarge 34 bold, feature titleMedium 19 semibold, subtitle bodySmall 14, and inherited header text. Decide whether home follows its actual Swift composition or semantic typography before changing global Flutter `TextTheme`.

Retain accessibility scaling and Flutter home single-column fallback (`home_screen.dart:295–305`). `IosPageHeader` already handles longer/larger titles with a scale-down path and a full semantic label; nominal token parity does not establish large-text usability.

## 4. Color and surface semantics

| Swift role | Flutter role | Important distinction |
|---|---|---|
| `primary`, `label` | `text`, `ColorScheme.onSurface` | Swift `primary` is foreground, not accent; Flutter scheme `primary` is accent |
| `background` | No single exact equivalent | Swift systemBackground; Flutter scaffold `background` is grouped-like light gray |
| `groupedBackground` | `background` | Flutter light `#F2F2F7`, dark `#000000` |
| `secondaryBackground` / home secondarySystemGroupedBackground | `surface` by component role | Flutter white / `#1C1C1E`; Swift background variants must not be collapsed indiscriminately |
| `tertiaryBackground` | `elevated` is only approximate | Flutter `#E9E9EF` / `#242426` |
| `secondaryLabel`, legacy `secondaryText` | `secondary` | Flutter `#606069` / `#B8B8C0` |
| `tertiaryLabel`, legacy `tertiaryText` | `tertiary` | Flutter `#73737D` / `#9898A2` |
| `quaternaryLabel` | Missing | Add only with an explicit low-emphasis use case |
| `separator`, legacy `border` | `separator`, scheme outlineVariant | Flutter `#D9D9DF` / `#38383A`; opacity behavior differs |
| `opaqueSeparator`, legacy `lightBorder` (separator × .7) | Missing exact roles | Flutter divider uses separator × .5 |
| `fill`, `secondaryFill`, `tertiaryFill`, `quaternaryFill` | Missing hierarchy | `surfaceContainerHighest = elevated` is not a four-level equivalent |
| `accent` | `accent`, scheme primary | Flutter `#0066CC` / `#69ADFF` |
| `accentSoft`, `accentMedium` | No named equivalents | Swift accent × .12 and × .25; Flutter repeats .12 locally |
| `success` | `success` | Swift systemGreen; Flutter `#208044` / `#72D694` |
| `warning` | `warning` | Swift systemOrange; Flutter `#9C5700` / `#FFBD62` |
| `error` | `error` | Swift systemRed; Flutter `#C83332` / `#FF8580` |
| `info` | Missing explicit role | Swift systemBlue; do not assume all informational UI is brand accent |

Flutter text is `#1C1C1E` / `#F5F5F7`. UIKit semantic colors adapt at runtime and are not a fixed hex palette. The app's `Resources/Assets.xcassets/AccentColor.colorset/Contents.json` contains no explicit color components, so an exact Swift accent hex cannot be established from that asset. “Quarter” should not be confused with `quaternaryLabel` or `quaternaryFill`, which are fourth-level color roles, or `accentMedium`, which is 25% opacity.

Swift home uses a systemBackground→systemGroupedBackground gradient, material empty/loading cards, and an interactive glass attendance card. Flutter uses a flat grouped scaffold, solid cards, and a primaryContainer gradient for attendance. Material, Liquid Glass, and solid fills require platform-specific rendering behind shared surface roles.

## 5. Shadow, stroke, dimensions, and motion

Swift shadows (`black` opacity, radius, x, y):

| Token | Opacity | Radius | Offset |
|---|---:|---:|---|
| xsmall | .04 | 2 | 0, 1 |
| small | .06 | 6 | 0, 2 |
| medium | .08 | 12 | 0, 4 |
| large | .12 | 24 | 0, 8 |
| xlarge | .16 | 40 | 0, 16 |

Legacy shadow colors are primary × .05 (`light`) and × .2 (`heavy`). Flutter has no shared shadow scale; Material cards explicitly use elevation 0 and a dark-only separator × .55 outline, while `AppCard` uses `Material` directly and does not inherit that CardTheme outline. Swift `subtleBorder` uses primary × .08 and width .5. Flutter blur/elevation is not a direct numerical substitute for Swift shadow radius.

| Swift animation token | Exact declaration | Flutter today |
|---|---|---|
| fast | spring response .25 s, dampingFraction .8 | No equivalent token |
| standard | spring response .35 s, dampingFraction .8 | No equivalent token |
| slow | spring response .5 s, dampingFraction .85 | No equivalent token |
| bounce | spring response .4 s, dampingFraction .65 | No equivalent token |
| easeOut | easeOut duration .25 s | No equivalent token |
| easeInOut | easeInOut duration .3 s | No equivalent token |

The quarter-second values are **250 ms**: fast spring response and easeOut duration. Spring response is not a fixed completion duration; an ease curve lasting 250 ms is not an exact spring match. There is no quarter-turn animation found in Flutter `lib`.

Flutter explicitly uses a 200 ms theme transition (`app.dart:264–267`) and 180 ms Moodle tab-controller animation (`course_widgets.dart:204–208`), each with a reduced-motion branch. Its Android and iOS page transitions both use `CupertinoPageTransitionsBuilder`; segmented controls retain framework motion. Swift home attaches fast-spring delays .3/.4/.5/.6/.65/.7 s, but `animateIn` starts true and is never changed in that source: do not describe this as an observed entrance animation. Swift buttons scale to .97 when pressed. No shared Swift reduced-motion handling appears in these audited shared/home sources.

Dimensions also need roles: Swift primary/secondary button heights 50/44; icon button 44 with icon size × .45; home settings icon 18 in 44; avatar dimensions 32/48/64 and text 12/18/24. Flutter shared circle buttons use minimum 50 with icon 21; header height 76 and leading width 70; shell item minimum height 66. Preserve comfortable touch targets rather than treating these as spacing constants.

## 6. Component inventory and duplication

| Swift implementation | Flutter implementation / usage | Recommendation |
|---|---|---|
| `NIUCard`, `cardBackground` | `AppCard`, `NiuCard`, Material `Card`, local `_HomeCard` | One card surface primitive with explicit padding/appearance variants; retain wrapper compatibility during migration |
| `NIUGlassCard`, `glassBackground`, direct `.glassEffect` | No actual glass equivalent | Shared semantic surface role, platform-specific implementation |
| `NIUButton`, `NIUSecondaryButton`, `PressableButtonStyle` | FilledButton/TextButton with mostly framework style | Define button roles, sizes, and motion without changing callbacks/loading semantics |
| `NIUIconButton`, home `iconButtonAppearance` | `CircleIconButton`, locally styled icon buttons | Consolidate appearance; home Swift uses 18 icon vs shared 19.8 at size 44 |
| `NIUTextField`, `MinimalTextField`, `MinimalSecureField` | Theme input decoration, `AppSearchField`, feature login fields | Shared field appearance; retain controller, focus, secure-entry and autofill behavior |
| `NIUChip`, home `InfoChip`, `NIUStatusBadge` | Event status badges, schedule badges, local selected controls | Separate metadata and status variants; match capsule/rectangular intent explicitly |
| `NIUAvatar` | Home/settings CircleAvatar | Appearance can align; initials extraction and displayed identity must remain intact |
| `NIUSectionHeader`, home today heading | `SectionHeader`, local headings | Shared role; preserve localized action text (`NIUSectionHeader` currently says “See All”) |
| `NIUEmptyState`, `NIULoadingState` | `NiuEmptyState`, `AppErrorState`, `AppLoadingState`, raw indicators | Common state anatomy; Flutter error already composes empty state, not an independent duplicate |
| `AcademicRefreshFooter` | `RelativeUpdateText` plus feature refresh/error UI | Presentation mapping only; preserve timestamp calculation and retry/state behavior |
| `FeatureCard`, `NIUQuickActionsGrid`/private `QuickActionCell`, `MinimalCard` | Home inline tiles, CampusServicesScreen rows, MoodleCourseCard | Share primitives; these have distinct content density and interactions |
| `MinimalToast`, `ToastView` | SnackBar calls | Define feedback colors/geometry separately from timing and delivery |

Swift legacy inventory: `MinimalCard` has a 50-point outlined icon circle and fixed black subtitle/chevron; both Minimal fields use black × .5 prompts; `MinimalToast` uses radius 25, padding 20×14, shadow black × .1/radius10/y5 and fixed black/white foregrounds. `ToastView` uses white text over primary × .8 with padding 20×12 and top offset 50. These are dark-mode review candidates, not proof of a visible runtime regression.

Feature usage searches found `ToastView` in both event registration tabs. No feature call sites were found for the four Minimal components, `NIUQuickActionsGrid`, `NIUSectionHeader`, `NIUChip`, or `NIUIconButton`; previews/definitions alone do not justify deleting them. Active shared Swift examples: login uses NIUTextField/NIUButton; schedule uses NIUButton; home uses avatar/glass cards; settings uses NIUCard/avatar.

Flutter consumers include:

- Cards: settings, calendar, Moodle resources/detail/information, registration, graduation, events, schedule, library. HeroCard: Moodle information, graduation summary, event detail.
- Search: calendar, events, Moodle. Shared segmented control: calendar, events, library. Moodle's `MoodleModuleSegments` is separate because it coordinates a horizontally scrollable six-tab controller (radii 16/13, item padding 3, minimum 64×48); it is not a drop-in duplicate of the nullable-value sliding control.
- Shared header: settings/privacy/credits, attendance, calendar, Moodle and viewers, events, schedule, login, library; campus services also uses it.
- Loading/error/empty states: calendar, Moodle, events, library, with feature-specific fallback and retry handling.

## 7. Hardcode inventory

Reproducible source-search snapshot, excluding tests: 72 Dart files under `mobile/lib`, 62 Swift files under `Features`. Counts are lexical occurrences, not unique design decisions or exhaustive UI violations.

| Pattern | Occurrences | Files |
|---|---:|---:|
| Flutter `NiuSpacing.` | 3 | 1 (`course_resource_tile.dart`: 8/12/8) |
| Flutter `NiuRadius.` | 0 | 0 |
| Flutter numeric `BorderRadius.circular(...)` | 29 | 12 |
| Flutter numeric `fontSize:` | 21 | 3 |
| Flutter `EdgeInsets.all/symmetric/only/fromLTRB(...)` | 120 | 28 |
| Swift feature `.font(.system(size: <number>...))` | 301 | 25 |
| Swift feature `Theme.Typography.` | 0 | 0 |

The EdgeInsets count includes token-based and zero calls and multiline expressions. It measures migration surface, not a count of numeric violations. Radius counts exclude vertical radii and constructors other than `BorderRadius.circular`.

High-value locations beyond home/shared:

| Location | Observed literals / overlap |
|---|---|
| `mobile/lib/app/campus_shell.dart` | .5 border, 66 min height, 4×10 padding, 24 icons; service rows 20 padding/24 radius |
| `features/grades/grades_screen.dart` | Repeated 24-radius panels/sheets, padding 20/24 |
| `features/schedule/schedule_screen.dart:331–492` | Outer 20/8/20/32; control radius14; card24; badge radius8, padding10×5 |
| `features/academic_calendar/calendar_screen.dart:154–655` | Outer20/12/20/32; day radius12; marker radius4; fixed font32/10/12; category colors blue/red/green/pink/purple/indigo/cyan/orange |
| `features/events/event_widgets.dart:11–35` | Status uses semantic palette but rectangular radius12 and padding10×6 |
| `features/graduation/graduation_dashboard.dart` | Outer20/8/20/32; divider semantic separator; progress radius8 |
| `features/settings/settings_screen.dart` | Outer20, avatar text28, privacy heading24 bold; local section/list-card wrappers |
| `features/attendance/attendance_screen.dart:220–232,298–301` | Explicit brightness-dependent green/amber/brown/blue status colors; card24/padding20 |
| `features/library/library_screen.dart:302–304` | Explicit white code-image backing and padding20; keep scanning contrast requirements distinct from generic surface color |
| `features/moodle/course_widgets.dart` | Material course card padding20; inter-element gaps10/14; local tab styling and timing described above |

Paths in this table beginning `features/` are relative to `mobile/lib/`. Status/category colors should receive domain roles only if their meanings are retained. Do not turn every calendar category into generic success/error just to reuse a palette.

## 8. App wiring and functional boundaries

Swift `NIUApp` sets transparent navigation bars with 18 medium title text, label tint, and opaque systemBackground tab bars. `NIUTabNavigationView` declares five tabs (home, Moodle, schedule, calendar, settings), but `RootView` selects login/home/logout state directly and overlays SSO refresh when needed. Appearance persists under `app.appearance.mode`.

Flutter `NiuApp` installs light/dark themes, zh-TW localization, GoRouter, service/session listeners and appearance persistence under `appearance`. Its shell has home/schedule/Moodle/campus; calendar and settings are separate pushed routes. `AuthGate` retains restoration and local-account rules. Deep-link allowlists differ between implementations. Neither route structures nor preference keys should change as a side effect of token alignment.

Preserve home course selection, current/next labels and data conditions, department normalization, initials, dates/Taipei formatting, refresh/cache/error states, grade/graduation calculations, calendar classifications, event availability, attendance callbacks, QR/barcode contents, login preservation, exports and generated PDF contents. Shared Flutter utilities include functional code (`openPublicUrl`, clock/relative update formatters); directory membership alone does not make them design tokens.

## 9. Recommended next steps

1. **Approve the contract:** exact spacing 4/8/12/16/24/32/48, radius 6/10/14/18/24/32/pill, semantic typography and color roles, and the status of Flutter-only 20 spacing/28 radius. Document deliberate platform surface and motion differences.
2. **Introduce compatible tokens:** preserve existing aliases while adding missing roles; use Flutter theme typography/extensions and Swift font roles where necessary. Keep quaternary colors, 25% accent, and 250 ms motion conceptually separate.
3. **Pilot home and shared primitives:** align page inset, card/control shape, section typography, icon/metadata treatments, and state presentation. Compare actual Swift home rather than the unused tab scaffold. Keep Material Card versus AppCard border behavior explicit.
4. **Migrate verified consumers:** cards, headers, fields, badges, states, then feature-local overrides. Mark unused legacy components for later call-site/build-target verification rather than deleting them during alignment.
5. **Validate the subsequent implementation:** light/dark home and representative calendar/Moodle/events/settings screens, narrow layouts, large text, reduced motion, keyboard/focus, and relevant existing navigation/session/data tests. Token-only changes should preserve feature outputs and all callbacks. No implementation or verification claims are made by this audit.
