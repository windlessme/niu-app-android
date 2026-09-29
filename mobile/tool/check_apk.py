"""Verify manifest/signature and ELF load alignment in a built Android APK."""
import argparse
from pathlib import Path
import struct
import subprocess
import zipfile

parser = argparse.ArgumentParser()
parser.add_argument("apk", type=Path)
parser.add_argument("--build-tools", type=Path, default=Path("/opt/android-sdk/build-tools/36.0.0"))
args = parser.parse_args()
subprocess.run([str(args.build_tools / "apksigner"), "verify", str(args.apk)], check=True)
badging = subprocess.check_output([str(args.build_tools / "aapt"), "dump", "badging", str(args.apk)], text=True)
assert "sdkVersion:'26'" in badging
assert "targetSdkVersion:'36'" in badging
assert "android.permission.MANAGE_EXTERNAL_STORAGE" not in badging
checked = []
with zipfile.ZipFile(args.apk) as archive:
    for name in archive.namelist():
        if not name.startswith(("lib/arm64-v8a/", "lib/x86_64/")) or not name.endswith('.so'):
            continue
        data = archive.read(name)
        assert data[:4] == b'\x7fELF', name
        assert data[4] == 2 and data[5] == 1, f'Unsupported ELF encoding: {name}'
        offset = struct.unpack_from('<Q', data, 32)[0]
        size, count = struct.unpack_from('<HH', data, 54)
        for index in range(count):
            header = offset + index * size
            kind = struct.unpack_from('<I', data, header)[0]
            if kind == 1:
                alignment = struct.unpack_from('<Q', data, header + 48)[0]
                assert alignment >= 16384, f'{name}: LOAD alignment {alignment} < 16KB'
        checked.append(name)
assert checked, 'No 64-bit libraries found'
print('APK signature, min/target SDK and ELF 16KB LOAD alignment verified')
print('\n'.join(checked))
print('This static check does not replace execution on a 16KB device.')
