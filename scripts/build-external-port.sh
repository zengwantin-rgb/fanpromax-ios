#!/bin/bash
set -euo pipefail
if [[ "${GITHUB_ACTIONS:-}" != "true" || "${RUNNER_ENVIRONMENT:-}" != "github-hosted" || "$(uname -s)" != "Darwin" ]]; then
  echo 'Compile and test only on a GitHub-hosted macOS runner.' >&2
  exit 1
fi
mkdir -p build/external/Payload/FanProMAX.app out
task_app_path=build/external/Payload/FanProMAX.app
task_output="$PWD/out/FanProMAX-iOS.ipa"
task_sdk_path="$(xcrun --sdk iphoneos --show-sdk-path)"
xcrun clang++ -std=c++17 -Wall -Wextra -Werror -UNDEBUG -fsanitize=address,undefined \
  -Isrc src/PortCore.cpp src/RemoteImage.cpp tests/remote_image_tests.cpp -o build/remote-image-tests
build/remote-image-tests | tee out/remote-image-tests.txt
xcrun clang++ -std=c++17 -Wall -Wextra -Werror -fobjc-arc -fsanitize=address,undefined \
  apps/ExternalPort/MemoryCheck.mm -framework Foundation -framework Security -o build/memory-check-host
build/memory-check-host --self-test | tee out/memory-check-host-tests.txt
task_flags=(-arch arm64 -isysroot "$task_sdk_path" -miphoneos-version-min=17.0 -std=c++17 -O2 -Wall -Wextra -Werror -Isrc -Iapps/ExternalPort)
xcrun --sdk iphoneos clang++ "${task_flags[@]}" -c src/RemoteImage.cpp -o build/ExternalRemoteImage.o
xcrun --sdk iphoneos clang++ "${task_flags[@]}" -fobjc-arc -c apps/ExternalPort/RemoteReader.mm -o build/ExternalReader.o
xcrun --sdk iphoneos clang++ "${task_flags[@]}" -fobjc-arc -c apps/ExternalPort/main.mm -o build/ExternalMain.o
xcrun --sdk iphoneos clang++ "${task_flags[@]}" -fobjc-arc -DNSP_HUD_HELPER=1 -c apps/ExternalPort/main.mm -o build/ExternalHUDMain.o
xcrun --sdk iphoneos clang++ "${task_flags[@]}" build/PortCore.o build/ExternalRemoteImage.o build/ExternalReader.o build/ExternalMain.o \
  -framework UIKit -framework Foundation -framework CoreGraphics -framework Security -o "$task_app_path/FanProMAX"
xcrun --sdk iphoneos clang++ "${task_flags[@]}" build/PortCore.o build/ExternalRemoteImage.o build/ExternalReader.o build/ExternalHUDMain.o \
  -framework UIKit -framework Foundation -framework CoreGraphics -framework Security -o "$task_app_path/FanProMAXHUD"
xcrun --sdk iphoneos clang -arch arm64 -isysroot "$task_sdk_path" -miphoneos-version-min=17.0 \
  -std=c11 -O2 -Wall -Wextra -Werror apps/ExternalPort/SpawnProbe.c -o "$task_app_path/NSPSpawnProbe"
xcrun --sdk iphoneos clang++ "${task_flags[@]}" -fobjc-arc apps/ExternalPort/MemoryCheck.mm \
  -framework Foundation -framework Security -o "$task_app_path/NSPMemoryCheck"
cp apps/ExternalPort/Info.plist "$task_app_path/Info.plist"
swift scripts/render-brand.swift build/Brand.xcassets/AppIcon.appiconset
xcrun actool build/Brand.xcassets --compile "$task_app_path" --platform iphoneos \
  --minimum-deployment-target 17.0 --target-device iphone --target-device ipad --app-icon AppIcon \
  --output-partial-info-plist build/brand-info.plist --output-format human-readable-text
python3 - "$task_app_path/Info.plist" <<'PY'
import plistlib,sys
from pathlib import Path
p=Path(sys.argv[1]);info=plistlib.loads(p.read_bytes())
info.update(plistlib.loads(Path('build/brand-info.plist').read_bytes()))
p.write_bytes(plistlib.dumps(info))
PY
cp apps/ExternalPort/ThirdPartyNotices.txt "$task_app_path/ThirdPartyNotices.txt"
cp apps/ExternalPort/Features.json "$task_app_path/Features.json"
plutil -lint "$task_app_path/Info.plist" apps/ExternalPort/Entitlements.plist apps/ExternalPort/HUDEntitlements.plist apps/ExternalPort/ProbeEntitlements.plist apps/ExternalPort/MemoryCheckEntitlements.plist
codesign --force --sign - --timestamp=none --pagesize 4096 --generate-entitlement-der \
  --entitlements apps/ExternalPort/MemoryCheckEntitlements.plist "$task_app_path/NSPMemoryCheck"
codesign --verify --strict --verbose=2 "$task_app_path/NSPMemoryCheck" 2>&1 | tee out/memory-check-signature.txt
codesign -d --entitlements :- "$task_app_path/NSPMemoryCheck" > out/memory-check-entitlements.plist
plutil -lint out/memory-check-entitlements.plist
codesign --force --sign - --timestamp=none --pagesize 4096 --generate-entitlement-der \
  --entitlements apps/ExternalPort/ProbeEntitlements.plist "$task_app_path/NSPSpawnProbe"
codesign --verify --strict --verbose=2 "$task_app_path/NSPSpawnProbe" 2>&1 | tee out/external-probe-signature.txt
codesign -d --entitlements :- "$task_app_path/NSPSpawnProbe" > out/external-probe-entitlements.plist
plutil -lint out/external-probe-entitlements.plist
codesign --force --sign - --timestamp=none --pagesize 4096 --generate-entitlement-der \
  --entitlements apps/ExternalPort/HUDEntitlements.plist "$task_app_path/FanProMAXHUD"
codesign --verify --strict --verbose=2 "$task_app_path/FanProMAXHUD" 2>&1 | tee out/external-hud-signature.txt
codesign -d --entitlements :- "$task_app_path/FanProMAXHUD" > out/external-hud-entitlements.plist
plutil -lint out/external-hud-entitlements.plist
codesign --force --sign - --timestamp=none --pagesize 4096 --generate-entitlement-der \
  --entitlements apps/ExternalPort/Entitlements.plist "$task_app_path"
codesign --verify --strict --verbose=2 "$task_app_path" 2>&1 | tee out/external-signature.txt
codesign -d --entitlements :- "$task_app_path/FanProMAX" > out/external-entitlements.plist
plutil -lint out/external-entitlements.plist
xcrun lipo "$task_app_path/FanProMAX" -verify_arch arm64
xcrun otool -L "$task_app_path/FanProMAX" | tee out/external-dependencies.txt
xcrun nm -u "$task_app_path/FanProMAX" | tee out/external-imports.txt
xcrun nm -u "$task_app_path/FanProMAXHUD" | tee out/external-hud-imports.txt
xcrun nm -u "$task_app_path/NSPSpawnProbe" | tee out/external-probe-imports.txt
xcrun nm -u "$task_app_path/NSPMemoryCheck" | tee out/memory-check-imports.txt
(cd build/external && /usr/bin/zip -qr "$task_output" Payload)
cp apps/ExternalPort/README.zh-CN.md out/FanProMAX-README.zh-CN.md
cp apps/ExternalPort/ThirdPartyNotices.txt out/FanProMAX-ThirdPartyNotices.txt
python3 scripts/verify_external.py | tee out/external-verification.json
