#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
adb wait-for-device
if [ "$(adb shell getprop sys.boot_completed | tr -d '\r')" != "1" ]; then
  echo 'Android device has not finished booting' >&2
  exit 1
fi
mkdir -p /tmp/opencode
adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb shell input keyevent KEYCODE_WAKEUP
adb shell wm dismiss-keyguard
adb shell am start -W -n me.windless.niulife/.MainActivity
adb shell uiautomator dump /sdcard/niu-window.xml
adb pull /sdcard/niu-window.xml /tmp/opencode/niu-window.xml
python3 - <<'PY'
from pathlib import Path
import re
import subprocess
import xml.etree.ElementTree as ET
text = Path('/tmp/opencode/niu-window.xml').read_text()
assert 'NIU-Life' in text, 'App did not expose the expected home screen'
root = ET.fromstring(text)
campus = next(node for node in root.iter('node') if '校園' ==
              (node.get('text', '') or node.get('content-desc', '')))
x1, y1, x2, y2 = map(int, re.findall(r'\d+', campus.get('bounds')))
subprocess.run(['adb', 'shell', 'input', 'tap', str((x1+x2)//2), str((y1+y2)//2)], check=True)
subprocess.run(['adb', 'shell', 'uiautomator', 'dump', '/sdcard/niu-services.xml'], check=True)
subprocess.run(['adb', 'pull', '/sdcard/niu-services.xml', '/tmp/opencode/niu-services.xml'], check=True)
root = ET.parse('/tmp/opencode/niu-services.xml').getroot()
calendar = next(node for node in root.iter('node') if '學年度行事曆' in
                (node.get('text', '') + node.get('content-desc', '')))
x1, y1, x2, y2 = map(int, re.findall(r'\d+', calendar.get('bounds')))
subprocess.run(['adb', 'shell', 'input', 'tap', str((x1+x2)//2), str((y1+y2)//2)], check=True)
subprocess.run(['adb', 'shell', 'uiautomator', 'dump', '/sdcard/niu-calendar.xml'], check=True)
subprocess.run(['adb', 'pull', '/sdcard/niu-calendar.xml', '/tmp/opencode/niu-calendar.xml'], check=True)
calendar_text = Path('/tmp/opencode/niu-calendar.xml').read_text()
assert '行事曆' in calendar_text and '今天' in calendar_text, 'Calendar route did not open'
subprocess.run(['adb', 'shell', 'screencap', '-p', '/sdcard/niu-calendar.png'], check=True)
subprocess.run(['adb', 'pull', '/sdcard/niu-calendar.png', '/tmp/opencode/niu-calendar.png'], check=True)
print('Android launch and calendar navigation smoke checks passed')
PY
