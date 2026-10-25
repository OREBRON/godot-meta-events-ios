#!/bin/bash
# Builds the no-op stub libraries that meta_sdk.gdextension loads on every
# platform except iOS, then fails unless each one exports meta_sdk_library_init.
#
# Tools: Apple clang (macOS), the Android NDK clang wrappers, and `zig cc` for
# Windows and Linux (brew install zig). Override the NDK with ANDROID_NDK.
set -euo pipefail

cd "$(dirname "$0")/.."
SRC="src/stub/meta_sdk_stub.c"
BIN="addons/meta_sdk/bin"
ENTRY="meta_sdk_library_init"

NDK="${ANDROID_NDK:-$HOME/Library/Android/sdk/ndk/28.2.13676358}"
NDK_BIN="$NDK/toolchains/llvm/prebuilt/darwin-x86_64/bin"

fail() { echo "build_stubs: $*" >&2; exit 1; }

command -v zig > /dev/null || fail "zig not found (brew install zig)"
[ -d "$NDK_BIN" ] || fail "Android NDK toolchain not found at $NDK_BIN (set ANDROID_NDK)"

mkdir -p "$BIN/macos" "$BIN/windows" "$BIN/linux" "$BIN/android"

# macOS: one universal dylib, checked per architecture.
MAC="$BIN/macos/libmeta_sdk_stub.macos.dylib"
clang -O2 -shared -fPIC -arch arm64 -arch x86_64 -mmacosx-version-min=11.0 -o "$MAC" "$SRC"
for arch in arm64 x86_64; do
	nm -arch "$arch" -gU "$MAC" | grep -q " T _$ENTRY\$" || fail "$MAC ($arch) does not export $ENTRY"
done

# Android: NDK clang for each ABI.
for pair in "arm64:aarch64-linux-android21" "arm32:armv7a-linux-androideabi21" "x86_64:x86_64-linux-android21"; do
	abi="${pair%%:*}"
	compiler="${pair#*:}-clang"
	out="$BIN/android/libmeta_sdk_stub.android.$abi.so"
	"$NDK_BIN/$compiler" -O2 -shared -fPIC -o "$out" "$SRC"
	"$NDK_BIN/llvm-nm" -D --defined-only "$out" | grep -q " T $ENTRY\$" || fail "$out does not export $ENTRY"
done

# Linux: zig cc.
LINUX="$BIN/linux/libmeta_sdk_stub.linux.x86_64.so"
zig cc -target x86_64-linux-gnu -O2 -shared -fPIC -o "$LINUX" "$SRC"
"$NDK_BIN/llvm-nm" -D --defined-only "$LINUX" | grep -q " T $ENTRY\$" || fail "$LINUX does not export $ENTRY"

# Windows: zig cc also writes an import library and a debug file next to the dll.
WIN="$BIN/windows/meta_sdk_stub.windows.x86_64.dll"
zig cc -target x86_64-windows-gnu -O2 -shared -o "$WIN" "$SRC"
rm -f "$BIN"/windows/*.lib "$BIN"/windows/*.pdb
"$NDK_BIN/llvm-objdump" -p "$WIN" | awk '/^Export Table:/ { in_exports = 1; next } in_exports' | grep -q "[[:space:]]$ENTRY\$" || fail "$WIN does not export $ENTRY"

echo "build_stubs: ok"
ls -l "$BIN"/macos/* "$BIN"/windows/* "$BIN"/linux/* "$BIN"/android/*
