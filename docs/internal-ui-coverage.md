# Internal content presentation coverage

This pass treats content hierarchy as well as layout. No API, parser, session,
storage or action callback changes. Existing tests supply synthetic data only.

| Feature | Internal coverage in this pass | Retained / not redesigned |
|---|---|---|
| Home / campus | centered icon/title/subtitle service cards | routing and greeting |
| Moodle list | title first, teacher/credits wrap together, quiet code; absent optional metadata omitted only in list | full details and model unknown values |
| Course announcements | shared item metadata lowered to caption | full text in discussion |
| Materials | detail content gutter, existing file actions | downloads and source URLs |
| Assignments | deadline label/value hierarchy; submission state emphasized and update time quiet | upload/clear/submit confirmations and consent |
| Forums / posts | author/time secondary to subject/body | pagination and attachments |
| Course grades | label/value fields replace undifferentiated metadata lines | grades, ranges, percentages, weights and feedback |
| Attendance | inherits prior status/date/time/source hierarchy | parser, scan confirmation, scanner contrast |
| Schedule options | reminder explanation secondary to switch title | export/configuration and permission flow |
| Graduation | progress-row vertical rhythm and remaining count hierarchy | original requirement and unknown semantics |
| Calendar details | category caption, source section typography | dates, notes and full source preserved |
| Library | usage explanation and timestamp secondary to code | barcode footprint and lifecycle |
| Registration | field labels secondary to values | certificate operations |
| Leave details / workflow | same shared label/value presentation | school status/order and cache |
| Event details | fact labels caption-level | application and change confirmation |
| Settings / legal / credits | action subtitles secondary | legal text is not summarized or removed |
| WebView / external documents | native wrappers retain common header/states | school/PDF content not restyled or injected |

Remaining visual acceptance: there is no rendered iOS screenshot set for every
feature. Camera, keyboard, file picker, live school forms and long real-world legal/
course content still require physical-device review. Existing dialogs keep platform
Material behavior rather than imitating iOS alerts. This is a cross-feature content
pass, not a claim that every screen has been visually compared pixel by pixel.
