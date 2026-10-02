"""Publish a verified local preview artifact to the dedicated download root."""
import argparse
import hashlib
import html
import json
import shutil
import subprocess
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("--apk", type=Path, required=True)
parser.add_argument("--version", required=True)
parser.add_argument("--destination", type=Path, default=Path("/srv/niu-downloads"))
parser.add_argument("--apksigner", default="/opt/android-sdk/build-tools/36.0.0/apksigner")
parser.add_argument("--keep", type=int, default=3, help="previews to keep, newest first")
args = parser.parse_args()
if not all(c.isalnum() or c in ".-_" for c in args.version):
    raise SystemExit("Invalid version")
subprocess.run([args.apksigner, "verify", str(args.apk)], check=True)
args.destination.mkdir(parents=True, exist_ok=True)
filename = f"NIU-Life-{args.version}-preview.apk"
target = args.destination / filename
temporary = target.with_suffix(".pending")
shutil.copyfile(args.apk, temporary)
temporary.chmod(0o644)
temporary.replace(target)
digest = hashlib.sha256(target.read_bytes()).hexdigest()
(args.destination / f"{filename}.sha256").write_text(f"{digest}  {filename}\n")
metadata = {"version": args.version, "file": filename, "bytes": target.stat().st_size, "sha256": digest}
(args.destination / "latest.json").write_text(json.dumps(metadata, indent=2) + "\n")
page = f'''<!doctype html><html lang="zh-Hant"><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>NIU-Life Android 下載</title>
<style>body{{font:17px system-ui;max-width:640px;margin:60px auto;padding:24px;background:#f2f2f7;color:#222}}a{{color:#286459}}.button{{display:inline-block;padding:16px 24px;background:#286459;color:white;border-radius:16px;text-decoration:none}}code{{overflow-wrap:anywhere;font-size:12px}}</style>
<h1>NIU-Life</h1><p>Android 開發預覽版 {html.escape(args.version)}</p>
<p><a class="button" href="{filename}">下載 APK · {target.stat().st_size / 1048576:.1f} MB</a></p>
<p>Android 8.0 以上。非官方校務工具，校務結果以學校系統為準。</p>
<p>此為開發測試版本，校務登入及各項功能仍需真實帳號與裝置驗證。</p>
<h3>檔案 SHA-256</h3><code>{digest}</code></html>'''
(args.destination / "index.html").write_text(page)



def version_key(path):
    """NIU-Life-0.13.10-preview.apk sorts after 0.13.9."""
    raw = path.name[len("NIU-Life-"):-len("-preview.apk")]
    return [int(part) if part.isdigit() else part for part in raw.replace("-", ".").split(".")]


# Each preview is ~200 MB; older ones are dropped with their checksums.
previews = sorted(args.destination.glob("NIU-Life-*-preview.apk"), key=version_key)
for old in previews[: max(0, len(previews) - max(args.keep, 1))]:
    if old.name == filename:
        continue
    old.unlink()
    old.with_name(f"{old.name}.sha256").unlink(missing_ok=True)
metadata["kept"] = [p.name for p in sorted(args.destination.glob("NIU-Life-*-preview.apk"), key=version_key)]
print(json.dumps(metadata, indent=2))
