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
cmp assets/campus_map/shixi.json ../app-content/campus-map/shixi.json
cmp assets/campus_map/dianzi.json ../app-content/campus-map/dianzi.json
cmp assets/campus_map/shihua.json ../app-content/campus-map/shihua.json
cmp assets/campus_map/gezhi.json ../app-content/campus-map/gezhi.json
cmp assets/campus_map/zonghe.json ../app-content/campus-map/zonghe.json
cmp assets/campus_map/tuzi.json ../app-content/campus-map/tuzi.json
cmp assets/campus_map/dongwu.json ../app-content/campus-map/dongwu.json
cmp assets/campus_map/shengzi.json ../app-content/campus-map/shengzi.json
cmp assets/campus_map/tiyu.json ../app-content/campus-map/tiyu.json
cmp assets/campus_map/xingzheng.json ../app-content/campus-map/xingzheng.json
cmp assets/campus_map/jingde.json ../app-content/campus-map/jingde.json
cmp assets/campus_map/tongshi.json ../app-content/campus-map/tongshi.json
cmp assets/campus_map/yuyan.json ../app-content/campus-map/yuyan.json
cmp assets/campus_map/huodong.json ../app-content/campus-map/huodong.json
cmp assets/campus_map/shipin.json ../app-content/campus-map/shipin.json
cmp assets/campus_map/campus.json ../app-content/campus-map/campus.json
dart format --output=none --set-exit-if-changed lib test integration_test
flutter analyze
flutter test
