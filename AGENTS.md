# Contribution workflow

All future changes must use a feature branch and pull request. Never push to
`main` directly, including documentation-only changes.

1. Create a focused branch from current `main`; implement and run relevant local checks.
2. Push the branch and open a PR describing scope, tests, risks and known limits.
3. Request an independent code review using a separate review subagent. Give it
   the complete PR diff and relevant context. It must not be the implementation
   agent. This instruction explicitly authorizes review delegation.
4. Resolve all blocking findings and request another review for the new HEAD.
5. Record the independent review on the PR: reviewer identity/session, exact HEAD
   SHA, findings, resolutions, and verdict. Only after a passing review, publish
   a comment containing `<!-- niu-code-review:FULL_HEAD_SHA -->`.
   Never publish this marker before the independent review has completed.
6. Wait for required CI checks and the recorded-review check on the current HEAD.
   Then squash-merge the PR and delete its branch. User approval is not required.
   Never use admin bypass or weaken checks to merge.

The recorded-review check attests that an independent review was performed; it
is not a GitHub approval from another GitHub account. The maintainer may post the
report on behalf of the review agent. New commits invalidate old review markers.

Bootstrap exception for installing the review workflow itself: comment/dispatch
workflows do not run until present on the default branch. After the independent
review of the exact installation HEAD, an authorized maintainer may publish the
same `Independent code review` check through GitHub's Checks API, linking the PR
review record. This does not waive review or CI and does not bypass protection.
Subsequent PRs use the installed workflow. Only `main` is long-lived; delete each
temporary branch after merging (repository auto-delete is enabled).

PR checks cover formatting, analysis, Flutter tests, school DOM fixtures,
calendar assets/toolchain contracts, public calendar validation and Android APK
build. Account-dependent tests remain manual; never put real credentials or
student documents in CI, PR comments, artifacts, or the repository.

If GitHub branch protection is unavailable for the repository plan, document the
limitation and still follow this workflow. Do not claim server-side enforcement.
