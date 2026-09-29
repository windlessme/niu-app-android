"""Keep declared tool versions in sync with the reproducible build files."""
import json
from pathlib import Path

root = Path(__file__).resolve().parents[1]
versions = json.loads((root / "toolchain.json").read_text())
assert (root / ".flutter-version").read_text().strip() == versions["flutter"]
settings = (root / "android/settings.gradle.kts").read_text()
assert f'version "{versions["androidGradlePlugin"]}"' in settings
assert f'version "{versions["kotlin"]}"' in settings
wrapper = (root / "android/gradle/wrapper/gradle-wrapper.properties").read_text()
assert f'gradle-{versions["gradle"]}-bin.zip' in wrapper
assert "distributionSha256Sum=" in wrapper
app = (root / "android/app/build.gradle.kts").read_text()
assert f'minSdk = {versions["androidMinSdk"]}' in app
assert f'targetSdk = {versions["androidTargetSdk"]}' in app
assert f'ndkVersion = "{versions["ndk"]}"' in app
workflow = (root.parent / ".github/workflows/android.yml").read_text()
assert f"flutter-version: '{versions['flutter']}'" in workflow
print("Toolchain declarations verified")
