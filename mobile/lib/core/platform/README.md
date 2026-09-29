# Android schedule integration

`ScheduleGateway` uses `niulife/schedule`; there are no Flutter package dependencies.
`exportScheduleIcs(snapshot)` produces the calendar string for `shareCalendar`.
Native FileProvider uses AndroidX Core 1.16.0 (declared in app Gradle).

## Snapshot v1

```json
{
  "version": 1,
  "timeZone": "Asia/Taipei",
  "semesterStart": "2026-09-14",
  "semesterEnd": "2027-01-15",
  "blocks": [{"id":"stable-course-block-id","title":"微積分","weekday":1,
    "startMinute":490,"endMinute":600,"room":"A101","teacher":"老師"}]
}
```

Dates are **inclusive actual semester civil dates**, not UTC instants or guessed
18-week defaults. The caller obtains/asks the user to confirm these dates.
Weekdays use ISO Monday=1 through Sunday=7; minutes are after Taipei midnight.
End is exclusive (up to 1440); overnight blocks must be split. IDs must be unique
within a snapshot and stable across re-exports. Limits: 200 blocks, 256 KiB, range
at most 366 days. No tokens, passwords, student IDs, or owner identity belong here.
Native validates before atomically replacing private `schedule_v1` preferences;
unknown versions are rejected. Android backup is disabled. Widget reads these
preferences directly and refreshes every 30 minutes (OS-controlled), on save,
on resume, reboot/time changes, and reminders.

The Swift exporter groups successive periods of the same course into blocks and
uses a user-selected start plus week count. Its shared clock uses Asia/Taipei.
For the Android caller, merge adjacent timetable rows only when course identity,
teacher and room match, flushing on an empty/different row. Pass the resulting
blocks here. Calendar export uses weekly UTC recurrence (Taipei fixed UTC+08:00),
starting on the first matching weekday on/after semester start and ending at
23:59:59 Taipei on semester end. Holidays are not inferred or excluded.

## App wiring owned by Flutter app

* After authenticated schedule fetch/account restore: `saveSnapshot(snapshot)`.
* On logout, account switch, session expiry, or clearing private data: **await
  `clear()`**, even if no new schedule was fetched. This removes private snapshot,
  reminder preferences, pending alarms/notifications, and cached ICS files, then
  renders the widget's logged-out state. An exported calendar already saved by
  another app is outside this app's control.
* Reminders: request notification permission following a user action; then call
  `setReminders(enabled: true, minutesBefore: 10)` (0–60). `false` means system
  notifications are unavailable. Preference persists and is retried on resume.
  Disable via `setReminders(enabled: false)`. Snapshot changes reschedule alarms.
* Share: `await gateway.shareCalendar(exportScheduleIcs(snapshot))`. Completion
  means the Android chooser opened, not that a calendar app imported the file.
* Android deep links: `niulife://schedule`, `niulife://attendance`,
  `niulife://library`. Flutter's built-in deep linking remains enabled. Route by
  URI **host** as well as path, including cold launch and warm new intents;
  enforce the same auth gates as in-app navigation. Shortcuts target attendance
  and library; widget/notification target schedule.

## Local notification limits

Only one next-class inexact alarm is pending; its receiver posts then schedules
the next occurrence. Reboot/package update/time change restores from preferences.
No exact-alarm, calendar-write, or storage permission is requested. Android Doze,
force-stop and OEM power controls can delay/suppress reminders; expired alarms
over one hour late are skipped. There is **no remote push backend or server-side
delivery**. These are local weekly class reminders, not campus push alerts.

## Verification

`flutter test test/core/platform/schedule_ics_test.dart` covers semester boundaries,
Taipei-to-UTC midnight rollover, recurrence, RFC escaping/UTF-8 folding and UIDs.
The coordinated Android build/device pass should verify widget add/resize, cold
and warm shortcuts, notification permission deny/grant, reboot restore, share
chooser URI read grants, and logout clearing. No APK build is run by this agent.
