#!/usr/bin/env bash
# Reproducible build of adb/fastboot for arm64 Android from AOSP platform-tools.
# Output: /work/adb/out/{adb,fastboot}
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
NDK=${NDK:-/Application/android-ndk-r29}
JOBS=${JOBS:-16}
API=${API:-30}

cd "$ROOT/sdk-tools"

if [ ! -d src/adb ] || [ ! -d src/openscreen ]; then
    echo "==> fetching AOSP sources (platform-tools-35.0.2)"
    python3 get_source.py --jobs 8
fi

apply_patch() {
    local repo=$1 patch=$2
    if git -C "$repo" apply --reverse --check "$patch" >/dev/null 2>&1; then
        echo "    already applied: $(basename "$patch")"
    elif git -C "$repo" apply --check "$patch" >/dev/null 2>&1; then
        git -C "$repo" apply "$patch"
        echo "    applied: $(basename "$patch")"
    else
        echo "    WARN: cannot apply $(basename "$patch") (context mismatch), skipped"
    fi
}

echo "==> applying local compatibility patches"
# libc++ (NDK r29) has no std::packaged_task<void() noexcept>
apply_patch src/openscreen  "$ROOT/patches-local/0001-task-runner-packaged-task.patch"
# fdsan double-tagging aborts adb server startup on Android 16
apply_patch src/libbase      "$ROOT/patches-local/0002-libbase-unique-fd-no-fdsan.patch"
apply_patch src/core         "$ROOT/patches-local/0003-libcutils-native-handle-no-fdsan.patch"
apply_patch src/libziparchive "$ROOT/patches-local/0004-libziparchive-no-fdsan.patch"

# fmt 10.2 + clang 21: consteval format-string checks fail; disable FMT_CONSTEVAL.
echo "==> building adb/fastboot (ndk r29, arm64-v8a, android-$API, shared bionic)"
python3 build.py \
    --ndk="$NDK" \
    --arch=aarch64 \
    --link=shared \
    --api="$API" \
    --target adb fastboot \
    --jobs="$JOBS" \
    -- -DCMAKE_CXX_FLAGS=-DFMT_CONSTEVAL=

mkdir -p "$ROOT/out"
cp build/ndk-shared-aarch64/bin/adb build/ndk-shared-aarch64/bin/fastboot "$ROOT/out/"
echo "==> done: $ROOT/out/adb $ROOT/out/fastboot"
