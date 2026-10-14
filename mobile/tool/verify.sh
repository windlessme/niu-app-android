#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 tool/sync_calendar.py --check
python3 tool/check_toolchain.py
python3 tool/check_architecture.py
node tool/check_academic_dom.js
node tool/check_schedule_lifecycle.js
cmp assets/LICENSE ../LICENSE
cmp assets/campus_map/jiaose.json ../app-content/campus-map/jiaose.json
cmp assets/campus_map/gongxue.json ../app-content/campus-map/gongxue.json
cmp assets/campus_map/campus.json ../app-content/campus-map/campus.json
dart format --output=none --set-exit-if-changed lib test integration_test
flutter analyze
flutter test
