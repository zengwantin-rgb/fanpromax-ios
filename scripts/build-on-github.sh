#!/bin/bash
set -euo pipefail
if [[ "${GITHUB_ACTIONS:-}" != true || "${RUNNER_ENVIRONMENT:-}" != github-hosted || "$(uname -s)" != Darwin ]]; then
  echo 'Compile and test only on GitHub-hosted macOS.' >&2
  exit 1
fi
mkdir -p build out
xcrun clang++ -std=c++17 -Wall -Wextra -Werror -UNDEBUG -fsanitize=address,undefined \
  -Isrc src/PortCore.cpp tests/core_tests.cpp -o build/core-tests
build/core-tests | tee out/core-tests.txt
task_sdk_path="$(xcrun --sdk iphoneos --show-sdk-path)"
xcrun --sdk iphoneos clang++ -arch arm64 -isysroot "$task_sdk_path" -miphoneos-version-min=17.0 \
  -std=c++17 -O2 -Wall -Wextra -Werror -Isrc -c src/PortCore.cpp -o build/PortCore.o
bash scripts/build-external-port.sh
cp analysis/apk-features.json out/
python3 - <<'PY'
import hashlib,json,os
from pathlib import Path
p=Path('out/FanProMAX-iOS.ipa')
r=json.loads(Path('out/external-build-info.json').read_text())
r.update(file=p.name,bytes=p.stat().st_size,sha256=hashlib.sha256(p.read_bytes()).hexdigest(),
 apk_direct_conversion=False,android_binaries_included=False,full_android_feature_port=False,
 aim_implemented=False,projectile_tracking_implemented=False,game_memory_writes=False,
 new_bundle_device_verified=False,installation='TrollStore',target_device='iPhone 15 Pro Max',
 project_repository=os.environ['GITHUB_REPOSITORY'])
Path('out/package-report.json').write_text(json.dumps(r,indent=2)+'\n')
Path('out/SHA256SUMS').write_text(f"{r['sha256']}  {p.name}\n")
PY
