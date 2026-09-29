#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 tool/sync_calendar.py --check
python3 tool/check_toolchain.py
node tool/check_academic_dom.js
node tool/check_schedule_lifecycle.js
cmp assets/LICENSE ../LICENSE
dart format --output=none --set-exit-if-changed lib test integration_test
flutter analyze
flutter test --concurrency="${FLUTTER_TEST_CONCURRENCY:-2}"
