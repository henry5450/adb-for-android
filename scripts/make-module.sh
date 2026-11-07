#!/usr/bin/env bash
# Build the KernelSU/Magisk module zip from prebuilt/ into dist/.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)

mkdir -p "$ROOT/dist"
cp "$ROOT/prebuilt/adb" "$ROOT/module/system/bin/adb.bin"
cp "$ROOT/prebuilt/fastboot" "$ROOT/module/system/bin/fastboot.bin"
chmod 755 "$ROOT/module/system/bin/"*.bin "$ROOT/module/system/bin/adb" "$ROOT/module/system/bin/fastboot" "$ROOT/module/customize.sh"

rm -f "$ROOT/dist/adb-fastboot-tools.zip"
( cd "$ROOT/module" && zip -r -q "$ROOT/dist/adb-fastboot-tools.zip" . )

echo "built $ROOT/dist/adb-fastboot-tools.zip"
