#!/bin/bash
set -euo pipefail
if [[ "${GITHUB_ACTIONS:-}" != true || "${RUNNER_ENVIRONMENT:-}" != github-hosted || "$(uname -s)" != Darwin ]]; then
  echo 'UI build and checks require a GitHub-hosted macOS runner.' >&2
  exit 1
fi
task_preview_app="$PWD/build/ui-preview/FanProMAX.app"
task_sim_id=""
preview_failure_logs() {
  task_failure_code=$?
  if [[ "$task_failure_code" -ne 0 && -n "$task_sim_id" ]]; then
    echo 'Cloud simulator diagnostics for this test app:'
    xcrun simctl spawn "$task_sim_id" log show --last 5m --style compact --predicate 'process == "FanProMAX"' 2>&1 | tail -n 100 || true
    python3 - <<'PYDIAG'
from pathlib import Path
paths=sorted((Path.home()/'Library/Logs/DiagnosticReports').glob('FanProMAX*'),key=lambda p:p.stat().st_mtime,reverse=True)
for path in paths[:3]:
    if path.is_file() and path.stat().st_size<3_000_000:
        print('SIMULATOR APP REPORT',path.name)
        print(path.read_text(errors='replace')[:26000])
PYDIAG
  fi
  return "$task_failure_code"
}
trap preview_failure_logs EXIT
mkdir -p "$task_preview_app" out/ui-preview
swiftc scripts/check-ui-capture.swift -o build/check-ui-capture
task_sim_sdk="$(xcrun --sdk iphonesimulator --show-sdk-path)"
task_sim_flags=(-target "$(uname -m)-apple-ios17.0-simulator" -isysroot "$task_sim_sdk" -std=c++17 -O1 -Wall -Wextra -Werror -UNDEBUG -fobjc-arc -DNSP_UI_PREVIEW=1 -Isrc -Iapps/ExternalPort)
xcrun clang++ "${task_sim_flags[@]}" src/PortCore.cpp src/RemoteImage.cpp apps/ExternalPort/RemoteReader.mm apps/ExternalPort/main.mm \
  -framework UIKit -framework Foundation -framework CoreGraphics -framework Security -framework UniformTypeIdentifiers -o "$task_preview_app/FanProMAX"
cp apps/ExternalPort/Info.plist "$task_preview_app/Info.plist"
cp apps/ExternalPort/Features.json "$task_preview_app/Features.json"
python3 - "$task_preview_app/Info.plist" <<'PY'
import plistlib,sys
from pathlib import Path
p=Path(sys.argv[1]);info=plistlib.loads(p.read_bytes())
info['CFBundleIdentifier']='io.github.zengwantin.fanpromax.preview'
info['CFBundleSupportedPlatforms']=['iPhoneSimulator']
p.write_bytes(plistlib.dumps(info))
PY
codesign --force --sign - "$task_preview_app"
xcrun simctl list devices available --json > build/ui-devices.json
task_sim_id="$(python3 - <<'PY'
import json
devices=json.load(open('build/ui-devices.json'))['devices']
phones=[d for key,values in devices.items() if 'iOS' in key for d in values if d['isAvailable'] and d['name'].startswith('iPhone')]
preferred=next((d for d in phones if d['name']=='iPhone 15 Pro Max'),phones[0] if phones else None)
assert preferred, 'No available iPhone simulator'
print(preferred['udid'])
PY
)"
xcrun simctl boot "$task_sim_id" || true
xcrun simctl bootstatus "$task_sim_id" -b
xcrun simctl status_bar "$task_sim_id" override --time '9:41' --dataNetwork wifi --wifiMode active --wifiBars 3 --batteryState charged --batteryLevel 100
xcrun simctl install "$task_sim_id" "$task_preview_app"
xcrun simctl launch "$task_sim_id" io.github.zengwantin.fanpromax.preview --nsp-smoke
task_sim_data="$(xcrun simctl get_app_container "$task_sim_id" io.github.zengwantin.fanpromax.preview data)"
task_smoke_path="$task_sim_data/tmp/NSPPreview/ui-smoke.json"
task_ui_ready="$task_sim_data/tmp/NSPPreview/ui-ready.json"
wait_ui_ready() {
  for task_poll in {1..60}; do
    if [[ -f "$task_ui_ready" ]]; then return 0; fi
    sleep 1
  done
  echo 'Timed out waiting for UIKit viewDidAppear.' >&2
  return 1
}
capture_ui() {
  for task_capture_attempt in {1..4}; do
    sleep 2
    xcrun simctl io "$task_sim_id" screenshot "$1"
    if build/check-ui-capture "$1"; then return 0; fi
  done
  echo 'No rendered NSP UI screenshot after retries.' >&2
  return 1
}
for task_poll in {1..90}; do
  if [[ -f "$task_smoke_path" ]]; then break; fi
  sleep 1
done
cp "$task_smoke_path" out/ui-preview/ui-smoke.json
python3 - <<'PY'
import json
result=json.load(open('out/ui-preview/ui-smoke.json'))
assert result['passed'], result
print(json.dumps(result,ensure_ascii=False,indent=2))
PY
for task_page in 0 1 2 3; do
  xcrun simctl terminate "$task_sim_id" io.github.zengwantin.fanpromax.preview || true
  sleep 2
  rm -f "$task_ui_ready"
  xcrun simctl launch "$task_sim_id" io.github.zengwantin.fanpromax.preview --nsp-page "$task_page"
  wait_ui_ready
  capture_ui "out/ui-preview/page-$task_page.png"
done
xcrun simctl terminate "$task_sim_id" io.github.zengwantin.fanpromax.preview
# Large text exercises wrapping and scrolling on the same real UIKit views.
xcrun simctl ui "$task_sim_id" content_size accessibility-extra-large
rm -f "$task_smoke_path"
rm -f "$task_ui_ready"
xcrun simctl launch "$task_sim_id" io.github.zengwantin.fanpromax.preview --nsp-smoke
for task_poll in {1..90}; do
  if [[ -f "$task_smoke_path" ]]; then break; fi
  sleep 1
done
cp "$task_smoke_path" out/ui-preview/ui-smoke-large-text.json
python3 - <<'PY'
import json
result=json.load(open('out/ui-preview/ui-smoke-large-text.json'))
assert result['passed'], result
PY
wait_ui_ready
capture_ui out/ui-preview/large-text.png
xcrun simctl terminate "$task_sim_id" io.github.zengwantin.fanpromax.preview
xcrun simctl ui "$task_sim_id" content_size large
rm -f "$task_ui_ready"
xcrun simctl launch "$task_sim_id" io.github.zengwantin.fanpromax.preview --nsp-widgets
wait_ui_ready
capture_ui out/ui-preview/widgets.png
xcrun simctl terminate "$task_sim_id" io.github.zengwantin.fanpromax.preview
xcrun simctl shutdown "$task_sim_id"
ditto -c -k --keepParent out/ui-preview out/FanProMAX-UI-preview.zip
rm -r out/ui-preview
