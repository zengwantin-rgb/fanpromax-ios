#!/bin/bash
set -euo pipefail
[[ "$RUNNER_ENVIRONMENT" == github-hosted && "$(uname -s)" == Darwin ]]
mkdir -p build/integrated-ui/FanProPreview.app out/integrated-ui
preview_app="$PWD/build/integrated-ui/FanProPreview.app"
preview_sdk="$(xcrun --sdk iphonesimulator --show-sdk-path)"
xcrun clang++ -target "$(uname -m)-apple-ios17.0-simulator" -isysroot "$preview_sdk" -std=c++17 -O1 -Wall -Wextra -Werror -fobjc-arc -fblocks -DFANPRO_UI_PREVIEW=1 -Isrc -Iapps/Integrated src/PortCore.cpp apps/Integrated/CollisionProbe.cpp apps/Integrated/Runtime.mm apps/Integrated/DiagnosticUpload.mm -framework UIKit -framework Foundation -framework Security -framework CoreGraphics -o "$preview_app/FanProPreview"
python3 - "$preview_app/Info.plist" <<'PY'
import plistlib,sys
from pathlib import Path
Path(sys.argv[1]).write_bytes(plistlib.dumps({'CFBundleIdentifier':'io.github.zengwantin.fanpromax.integrated.preview','CFBundleExecutable':'FanProPreview','CFBundleName':'FanProPreview','CFBundlePackageType':'APPL','CFBundleVersion':'1','CFBundleShortVersionString':'1.0','MinimumOSVersion':'17.0','UIDeviceFamily':[1],'UILaunchScreen':{}}))
PY
codesign --force --sign - "$preview_app"
xcrun simctl list devices available --json > build/integrated-devices.json
preview_id="$(python3 - <<'PY'
import json
p=[d for runtime,values in json.load(open('build/integrated-devices.json'))['devices'].items() if 'iOS' in runtime for d in values if d['isAvailable'] and d['name'].startswith('iPhone')]
print(next((d for d in p if d['name']=='iPhone 15 Pro Max'),p[0])['udid'])
PY
)"
xcrun simctl boot "$preview_id" || true
xcrun simctl bootstatus "$preview_id" -b
xcrun simctl install "$preview_id" "$preview_app"
xcrun simctl launch "$preview_id" io.github.zengwantin.fanpromax.integrated.preview
preview_data="$(xcrun simctl get_app_container "$preview_id" io.github.zengwantin.fanpromax.integrated.preview data)"
for preview_poll in {1..90}; do
  [[ -f "$preview_data/tmp/integrated-ui.json" ]] && break
  sleep 1
done
cp "$preview_data/tmp/integrated-ui.json" out/integrated-ui/report.json
python3 - <<'PY'
import json
p=json.load(open('out/integrated-ui/report.json'));print(json.dumps(p,indent=2));assert p['passed'],p
PY
xcrun simctl io "$preview_id" screenshot out/integrated-ui/preview.png
xcrun simctl terminate "$preview_id" io.github.zengwantin.fanpromax.integrated.preview
xcrun simctl shutdown "$preview_id"
