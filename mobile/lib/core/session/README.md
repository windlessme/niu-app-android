# Shared session and home timetable

Use `CampusSession.instance` (a `ChangeNotifier`) in `ListenableBuilder` or an
app-owned provider. Call `await restore()` before deciding the initial route.

* `isSignedIn`: remotely verified identity with a usable in-memory token.
* `isOffline`: saved identity and cache restored after a transient verification
  failure. This does **not** authorize online requests. Allow cached schedule/home
  views in this state and show a visible offline label and login/retry action.
  Use `await retryRestore()` for an explicit network retry; `restore()` coalesces
  the initial load and does not repeatedly send requests after an outage.
* `cachedSchedule`: nullable `CachedSchedule`, loaded only when its `account`
  matches the saved account. Fresh schedule extraction persists it automatically.
* `cachedSchedule.today({DateTime? now})`: records with `period`, `time`, `course`.
  Converts the supplied instant to Taipei time before selecting ISO weekday.
* `cachedSchedule.coursesForWeekday(int weekday)`: Monday=1 through Sunday=7;
  omitted days return an empty list. `course` preserves teacher/course/room lines.
* `cachedSchedule.fetchedAt`: UTC fetch timestamp; display its age for stale data.
* `cachedSchedule.rows`: original school table, consumable by
  `ClassSchedule.fromRows` for the existing `ScheduleView`.

`await logout()` immediately invalidates epochs and in-memory identity/cache,
persists `pendingCleanup=true`, waits for in-flight writes, and attempts **every**
feature, native schedule, cookie, web-storage, WebView-cache and credential cleanup.
Failures retain the marker and block new authentication. `restore()` and
`acceptToken()` call `recoverCleanup()` before proceeding. A restart therefore
retries incomplete cleanup. The device vault never removes the pending marker
while clearing credentials; only complete cleanup writes it to `false`.

Register additional service cleanup with `registerCleanup(callback)`. Callbacks
must be idempotent because recovery retries them. The parent can display
`cleanupPending` and retry `logout()`; do not navigate to authenticated content
after a cleanup error.

An HTTP 401/403 or identity mismatch during restore triggers cleanup. A transport
failure retains cached schedule/widget data and enters explicit offline state.
No password is persisted. An offline account must be logged out before switching
to another account.
