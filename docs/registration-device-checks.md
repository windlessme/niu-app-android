# Registration PDF device checks

Status: test plan only; no device results recorded. Bind these checks to the final public interface when registration implementation is ready.

## Setup and synthetic fixtures

- Use a debug build, an Android emulator at the supported minimum API and a current API, and one physical Android device. Record build revision, OS/API, device, document provider, and PDF viewer/receiver versions.
- Use a fixture-backed registration service and two fictional accounts, `TEST-A` and `TEST-B`. Do not use real university credentials, student records, cookies, or personal files. All network responses in these checks should come from fixtures.
- Generate a valid two-page PDF locally with a PDF library or Android `PdfDocument`: page 1 says `SYNTHETIC REGISTRATION — TEST-A`, page 2 says `PAGE 2 — NOT AN OFFICIAL DOCUMENT`. Include a border and distinct corner markers so clipping and orientation are visible. Use a supported font. Generate a second PDF marked `TEST-B`.
- Record each fixture's byte length and SHA-256. A `%PDF-` header alone is not a valid render fixture. Prepare empty bytes, HTML login content, a truncated PDF, and a header-only PDF as separate failure fixtures. Add a fixture above the final documented size limit.
- Use only a disposable output folder and a local test share receiver. The receiver should report intent type, URI scheme, permission flags, and received byte hash without uploading data.

## Native preview / PDF rendering

1. Open A's certificate. Verify actual rendered page content, page count, corner markers, orientation, scrolling/page navigation, and zoom if offered. A successful channel callback alone does not establish render success.
2. Close and reopen preview repeatedly; background/resume and rotate while previewing. Expect no crash, stuck loading state, blank restored page, or unbounded resource growth. Native renderer, page, and file-descriptor resources must be released when their owner closes.
3. Preview must not create a user-visible Downloads document or report that the document has been saved.
4. If preview uses an external viewer, test with a viewer installed and with none available. Expect a readable error/recovery path for the latter. If preview uses in-app `PdfRenderer`, repeat on a device with no external viewer to verify rendering is independent of one.
5. Feed each invalid fixture through the public document flow. Expect a recoverable validation/render error, no false success, and a successful subsequent valid preview. Check unsupported/encrypted PDFs if they fall within the final input contract.

## Save and cancellation

1. Save A's PDF through Android's document creation UI into the disposable folder. Confirm PDF MIME type, sensible filename, and user-selected destination. Verify saved bytes match the fixture hash and both pages render.
2. Cancel with Back and the picker's cancel control where available. Expect cancellation rather than a success message, loading cleared, and an immediately usable retry.
3. Repeat save with an existing filename and exercise the provider's replace/rename behavior. Verify the chosen result has the exact fixture bytes.
4. Exercise a provider write failure (for example, a test document provider that throws on write). Expect a save error and retry, never success. Record whether the provider leaves an empty/partial output; do not mistake it for a valid saved certificate.
5. Tap save rapidly and attempt preview/share while the picker is open. Expect one coherent active save, a defined busy/disabled response, and no overwritten pending callback or wrong PDF output.
6. Cancel, fail, and succeed in successive attempts. Every request must settle once; a late result from an older attempt must not complete a newer attempt.

## Share / external handoff

If sharing is supported, use the explicit share action; otherwise record it as not applicable and run the URI checks against external preview.

- Verify `application/pdf`, a `content://` URI, temporary read access, and a stream/ClipData payload suitable for the chosen intent. No student endpoint, cookies, credentials, or `file://` path should be handed off.
- Select the local receiver and verify its received hash matches A's fixture. The receiver should not need broad storage permission or receive write access.
- Dismiss the chooser, return from the receiver, and retry. Opening/dismissing a chooser must not claim that a destination saved the file or that the recipient completed processing it.
- Verify exposed provider paths are limited to intended exports. Check that immediate cleanup does not break a receiver still reading the document; record the intended expiration/cleanup policy and verify it.

## Lifecycle and account guard

Use controlled delayed fixture responses and, for an open picker, a test harness that can invalidate the session independently of the foreground registration screen.

| Scenario | Required observation |
| --- | --- |
| Start A fetch, leave registration, then deliver response | No navigation resurrection, disposed-state exception, or automatic document launch. |
| Start A fetch, log out or switch to B, then deliver A response | A's result is discarded; B cannot preview/save/share A's bytes or see A's status. |
| Preview A, invalidate A, then return/resume | A's cached document/actions are no longer available in the app; B requires B's own fixture. |
| Open A save picker, invalidate A, then select a destination | Pending A work is invalidated; no A bytes written after invalidation and no stale success applied to B. A provider-created empty file is not a successful save. |
| Open picker, rotate/recreate Activity, then save or cancel | No crash or permanently pending action. Recover or cancel coherently; a fresh save works. |
| Kill the app process while picker/viewer is foreground, then return | Safe startup with correct account ownership; no automatic replay of A's operation. |
| Invalidate A repeatedly while save/preview is pending | Cleanup is idempotent, callbacks settle at most once, and later activity results do not revive cleared operations. |
| Fetch and save B after each interruption | Only B markers and hash appear, proving both recovery and ownership isolation. |

Repeat account invalidation immediately before and immediately after response delivery to cover race boundaries. Inspect only synthetic app-private document cache in the debug build to confirm the final cleanup policy. Files explicitly exported before logout and bytes already read by an external recipient cannot be recalled; distinguish those from new post-invalidation exports.

## Execution evidence and eventual automation

- Record each case as PASS, FAIL, BLOCKED, or N/A with build/device and concise reproduction steps. Attach only synthetic screenshots and redacted logs. Do not claim device coverage from Dart unit/widget tests.
- After the API stabilizes, map these scenarios to `mobile/integration_test/registration_native_test.dart` using fixture injection. Keep actual Android rendering and channel calls active; mocking the bridge does not verify native behavior. Use Android instrumentation/UI Automator or manual steps for system pickers, choosers, process death, and receiver permissions that Flutter tests cannot drive directly.
- Prioritize exact saved-byte verification, save cancellation/retry, real render completion, and delayed A-to-B ownership races. Document any manual-only checks and rerun failures after fixes.
- Delete disposable exports and reset emulator/test receiver data after recording results.
