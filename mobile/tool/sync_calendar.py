"""Copy canonical public calendar snapshots into Flutter assets."""
import argparse
import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parents[2]
source = root / "calendar-data"
target = root / "mobile/assets/academic_calendar"
parser = argparse.ArgumentParser()
parser.add_argument("--check", action="store_true")
args = parser.parse_args()
index = json.loads((source / "index.json").read_text())
for entry in index["calendars"]:
    expected_path = f"years/{entry['academicYear']}.json"
    if entry["path"] != expected_path:
        raise SystemExit(f"Unexpected calendar path: {entry['path']}")
    if hashlib.sha256((source / expected_path).read_bytes()).hexdigest() != entry["sha256"]:
        raise SystemExit(f"Calendar source hash mismatch: {expected_path}")
paths = ["index.json"] + [entry["path"] for entry in index["calendars"]]
for relative in paths:
    src, dst = source / relative, target / relative
    if args.check:
        if not dst.exists() or src.read_bytes() != dst.read_bytes():
            raise SystemExit(f"Calendar asset out of date: {relative}")
    else:
        dst.parent.mkdir(parents=True, exist_ok=True)
        dst.write_bytes(src.read_bytes())
print(f"Calendar assets {'verified' if args.check else 'synced'}: {len(paths)}")
