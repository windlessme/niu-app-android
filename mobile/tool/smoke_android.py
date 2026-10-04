#!/usr/bin/env python3
"""Smoke-test the debug APK on a booted Android device or emulator.

Starts from a clean install, signs in with the Play review demo account
(demo mode never contacts the school), then opens every main tab, every
campus service on the home grid and the notification settings, checking
each page appears and Flutter logs no error. Screenshots go to the output
folder so a failure can be looked at afterwards.

    NIU_DEMO_PASSWORD=… python3 tool/smoke_android.py [--no-install] [--out DIR]

The demo password is not in the repository; without it only the login
screen is checked.
"""
import argparse
import os
import re
import subprocess
import sys
import tempfile
import time
import xml.etree.ElementTree as ET
from pathlib import Path

PACKAGE = "me.windless.niulife"
APK = Path(__file__).resolve().parent.parent / "build/app/outputs/flutter-apk/app-debug.apk"
DEMO_ACCOUNT = "niulifedemo"
# Home grid tiles, in the order they appear, with text that proves the page opened.
SERVICES = [
    ("校園信箱", "收件匣"),
    ("成績", "成績"),
    ("圖書館", "入館 QR Code"),
    ("行事曆", "行事曆"),
    ("畢業門檻", "畢業門檻"),
    ("請假", "請假紀錄"),
    ("活動報名", "活動"),
    ("在學證明", "在學證明"),
    ("郵件包裹", "查詢結果"),
]
FLUTTER_ERROR = re.compile(r"E/flutter|E flutter|Another exception was thrown|══╡ EXCEPTION")


class Smoke:
    def __init__(self, out: Path):
        self.out = out
        self.step = 0

    def adb(self, *args: str, check: bool = True) -> str:
        return subprocess.run(["adb", *args], check=check, capture_output=True, text=True).stdout

    def nodes(self) -> list[ET.Element]:
        self.adb("shell", "uiautomator", "dump", "/sdcard/niu-smoke.xml")
        xml = self.adb("exec-out", "cat", "/sdcard/niu-smoke.xml")
        return list(ET.fromstring(xml[xml.index("<"):]).iter("node"))

    @staticmethod
    def label(node: ET.Element) -> str:
        # Flutter exposes text as content-desc and field hints as hint.
        return "\n".join(node.get(k) or "" for k in ("text", "content-desc", "hint"))

    def find(self, text: str, exact: bool = False, widget: str | None = None) -> ET.Element | None:
        """exact: one line of the label equals text; otherwise any substring."""
        for node in self.nodes():
            if widget and not (node.get("class") or "").endswith(widget):
                continue
            parts = self.label(node).split("\n")
            if (text in parts) if exact else (text in self.label(node)):
                return node
        return None

    def wait(
        self, text: str, timeout: float = 20, exact: bool = False, widget: str | None = None, scroll: bool = False
    ) -> ET.Element:
        """scroll: swipe the page up between tries, for items below the fold."""
        deadline = time.time() + timeout
        while time.time() < deadline:
            node = self.find(text, exact, widget)
            if node is not None:
                return node
            if scroll:
                self.adb("shell", "input", "swipe", "540", "1700", "540", "900", "300")
            time.sleep(1)
        self.shot(f"missing-{text}")
        raise AssertionError(f"「{text}」did not appear within {timeout:.0f}s")

    def tap(
        self, text: str, exact: bool = False, timeout: float = 20, widget: str | None = None, scroll: bool = False
    ) -> None:
        node = self.wait(text, timeout, exact, widget, scroll)
        x1, y1, x2, y2 = map(int, re.findall(r"\d+", node.get("bounds")))
        self.adb("shell", "input", "tap", str((x1 + x2) // 2), str((y1 + y2) // 2))

    def back(self) -> None:
        self.adb("shell", "input", "keyevent", "KEYCODE_BACK")

    def shot(self, name: str) -> None:
        self.step += 1
        png = subprocess.run(["adb", "exec-out", "screencap", "-p"], check=True, capture_output=True).stdout
        (self.out / f"{self.step:02d}-{name}.png").write_bytes(png)

    def check_log(self, where: str) -> None:
        errors = [l for l in self.adb("logcat", "-d").splitlines() if FLUTTER_ERROR.search(l)]
        if errors:
            (self.out / "flutter-errors.txt").write_text("\n".join(errors), encoding="utf-8")
            raise AssertionError(f"Flutter logged errors at {where}:\n" + "\n".join(errors[:10]))

    def type_into(self, hint: str, value: str) -> None:
        self.tap(hint, exact=True, widget="EditText")
        time.sleep(1.5)  # keystrokes sent while the keyboard opens are lost
        self.adb("shell", "input", "text", value)
        time.sleep(0.5)

    def dismiss_announcements(self, seconds: float = 6) -> None:
        """Close any popup announcement published in app-content."""
        deadline = time.time() + seconds
        while time.time() < deadline:
            if self.find("知道了", exact=True) is not None:
                self.tap("知道了", exact=True)
            elif self.find("校園服務") is not None:
                return
            time.sleep(1)

    def home(self) -> None:
        self.tap("第 1 個分頁", timeout=10)
        self.wait("校園服務")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--no-install", action="store_true", help="use the APK already on the device")
    parser.add_argument("--out", type=Path, help="screenshot folder (default: a new temporary folder)")
    args = parser.parse_args()
    out = args.out or Path(tempfile.mkdtemp(prefix="niu-smoke-"))
    out.mkdir(parents=True, exist_ok=True)
    s = Smoke(out)
    print(f"Screenshots: {out}")

    s.adb("wait-for-device")
    if s.adb("shell", "getprop", "sys.boot_completed").strip() != "1":
        print("Android device has not finished booting", file=sys.stderr)
        return 1
    if not args.no_install:
        if not APK.exists():
            print(f"Build the APK first: flutter build apk --debug ({APK} missing)", file=sys.stderr)
            return 1
        s.adb("install", "-r", str(APK))
    s.adb("shell", "pm", "clear", PACKAGE)
    s.adb("shell", "input", "keyevent", "KEYCODE_WAKEUP")
    s.adb("shell", "wm", "dismiss-keyguard", check=False)
    s.adb("logcat", "-c")
    s.adb("shell", "am", "start", "-W", "-n", f"{PACKAGE}/.MainActivity")

    # A fresh install opens the home screen as a guest.
    s.dismiss_announcements(seconds=40)
    s.wait("校園服務", timeout=10)
    s.shot("guest-home")
    s.tap("登入校務系統")
    s.wait("學號", exact=True, widget="EditText")
    s.shot("login")
    s.check_log("login")
    password = os.environ.get("NIU_DEMO_PASSWORD")
    if not password:
        print("Login screen OK. Set NIU_DEMO_PASSWORD to walk through the demo account.")
        return 0

    s.type_into("學號", DEMO_ACCOUNT)
    # Never submit a mistyped account: anything but the demo account goes to the school.
    fields = [n for n in s.nodes() if (n.get("class") or "").endswith("EditText")]
    typed = fields[0].get("text") if fields else None
    if typed != DEMO_ACCOUNT:
        s.shot("mistyped-account")
        raise AssertionError(f"account field reads {typed!r}, not {DEMO_ACCOUNT!r}; not signing in")
    s.type_into("密碼", password)
    s.adb("shell", "input", "keyevent", "KEYCODE_BACK")  # hide the keyboard
    s.tap("登入", exact=True, widget="Button")
    s.wait("示範模式", timeout=40)
    s.wait("校園服務")
    s.shot("home")
    s.check_log("home")

    for tab, proof in (("第 2 個分頁", "星期"), ("第 3 個分頁", "門課程")):
        s.tap(tab)
        s.wait(proof)
        s.shot(proof)
        s.check_log(tab)
    s.home()

    for tile, proof in SERVICES:
        s.tap(tile + "，", scroll=True)  # tiles read 「校園信箱，收信、寫信與附件」
        s.wait(proof, timeout=30)
        time.sleep(1)
        s.shot(tile)
        s.check_log(tile)
        s.back()
        s.wait("校園服務", scroll=True)
        print(f"  ✓ {tile}")

    for _ in range(3):  # back to the top of home, where the gear is
        s.adb("shell", "input", "swipe", "540", "700", "540", "1900", "200")
    s.tap("設定", exact=True)
    s.tap("通知設定", scroll=True)
    s.wait("上課中通知")
    s.shot("notification-settings")
    s.check_log("notification settings")
    s.back()
    s.back()
    s.wait("校園服務")
    print("Android smoke test passed: login, three tabs, every campus service, notification settings")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (AssertionError, subprocess.CalledProcessError) as error:
        print(f"Smoke test failed: {error}", file=sys.stderr)
        sys.exit(1)
