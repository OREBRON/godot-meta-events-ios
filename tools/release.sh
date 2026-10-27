#!/bin/bash
# Builds everything, runs the tests and packs addons/meta_sdk into
#   dist/godot-meta-events-ios-<version>.zip
# where <version> comes from addons/meta_sdk/plugin.cfg. The zip's root is
# addons/meta_sdk/, ready to unzip at a game's project root.
#
# The zip is made with `zip -y` so the symlinks inside Meta's xcframeworks stay
# symlinks; flattened copies no longer match Meta's signatures. After zipping
# the script lists the archive and fails unless every file a game needs is in
# it, nothing from .godot/, vendor/ or build/ is, the symlinks survived and the
# xcframeworks still pass `codesign --verify --strict` when unzipped.
#
# dist/ only ever holds a zip that passed those checks: the old release zip is
# removed before anything is built, the new one is written to build/release/ and
# moved into dist/ as the last step.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
ADDON="addons/meta_sdk"
STAGE="build/release/stage"
VERIFY="build/release/verify"

fail() { echo "release: $*" >&2; exit 1; }

VERSION="$(sed -n 's/^version="\([^"]*\)".*/\1/p' "$ADDON/plugin.cfg")"
[ -n "$VERSION" ] || fail "no version=\"...\" line in $ADDON/plugin.cfg"
RELEASE_ZIP="$ROOT/dist/godot-meta-events-ios-$VERSION.zip"
ZIP="$ROOT/build/release/godot-meta-events-ios-$VERSION.zip"
echo "release: version $VERSION"

# A failure anywhere below must not leave an earlier release (or a rejected
# candidate) looking current.
rm -f "$RELEASE_ZIP" "$ZIP"
# A staged copy left in the project (build/release/stage/addons/meta_sdk) would
# be a second class_name MetaSDK if build/.gdignore were missing.
rm -rf "$STAGE" "$VERIFY"

tools/build_stubs.sh
tools/build_ios.sh
import_log="$ROOT/build/release/import.log"
mkdir -p "$(dirname "$import_log")"
godot --headless --path . --import > "$import_log" 2>&1 || { cat "$import_log" >&2; fail "godot --import failed"; }
tools/run_tests.sh

# Stage a copy without Finder junk; rsync -a keeps symlinks.
rm -rf "$STAGE" "$VERIFY"
mkdir -p "$STAGE/$ADDON"
rsync -a --exclude .DS_Store "$ADDON/" "$STAGE/$ADDON/"

(cd "$STAGE" && zip -qry "$ZIP" addons)
[ -f "$ZIP" ] || fail "zip did not write $ZIP"

# Content check.
entries="$(unzip -Z1 "$ZIP")"
missing=0
reported=" "
require() {
	case "$reported" in *" $1 "*) return ;; esac
	if ! grep -Fxq -- "$ADDON/$1" <<< "$entries"; then
		echo "release: missing from zip: $ADDON/$1" >&2
		missing=1
		reported="$reported$1 "
	fi
}

for file in plugin.cfg plugin.gd meta_sdk.gd meta_sdk.gdextension \
	export/meta_sdk_ios_plist.gd export/meta_sdk_ios_export_plugin.gd export/meta_sdk_ios_frameworks.gd; do
	require "$file"
	case "$file" in *.gd | *.gdextension) require "$file.uid" ;; esac
done
# Every export script in the source tree, so a new one cannot be left out.
for file in "$ADDON"/export/*.gd; do
	require "export/$(basename "$file")"
	require "export/$(basename "$file").uid"
done

XCFRAMEWORKS=(meta_sdk.ios.template_debug meta_sdk.ios.template_release FBSDKCoreKit FBSDKCoreKit_Basics FBAEMKit)
for name in "${XCFRAMEWORKS[@]}"; do
	require "bin/ios/$name.xcframework/Info.plist"
done
# Without it every game export packs Meta's 53 MB of *.abi.json (tools/build_ios.sh).
require "bin/ios/.gdignore"

for file in macos/libmeta_sdk_stub.macos.dylib windows/meta_sdk_stub.windows.x86_64.dll \
	linux/libmeta_sdk_stub.linux.x86_64.so android/libmeta_sdk_stub.android.arm64.so \
	android/libmeta_sdk_stub.android.arm32.so android/libmeta_sdk_stub.android.x86_64.so; do
	require "bin/$file"
done

unexpected="$(grep -E '(^|/)(\.godot|vendor|build)/|\.DS_Store$' <<< "$entries" || true)"
if [ -n "$unexpected" ]; then
	echo "release: zip must not contain .godot/, vendor/, build/ or .DS_Store:" >&2
	head -n 20 <<< "$unexpected" >&2
	missing=1
fi
outside="$(grep -vE "^$ADDON(/|\$)|^addons/\$" <<< "$entries" || true)"
if [ -n "$outside" ]; then
	echo "release: zip has entries outside $ADDON/:" >&2
	head -n 20 <<< "$outside" >&2
	missing=1
fi

# Symlinks: the archive must hold as many as the staged copy, and Meta's
# FBSDKCoreKit must have some (its Mac Catalyst slice is a versioned bundle).
staged_links="$(find "$STAGE" -type l | wc -l | tr -d ' ')"
zipped_links="$(unzip -Z "$ZIP" | grep -c '^l' || true)"
core_links="$(unzip -Z "$ZIP" "$ADDON/bin/ios/FBSDKCoreKit.xcframework/*" | grep -c '^l' || true)"
[ "$staged_links" -gt 0 ] || { echo "release: staged copy has no symlinks" >&2; missing=1; }
[ "$zipped_links" = "$staged_links" ] || { echo "release: zip stores $zipped_links symlinks, staged copy has $staged_links" >&2; missing=1; }
[ "$core_links" -gt 0 ] || { echo "release: FBSDKCoreKit.xcframework has no symlinks in the zip" >&2; missing=1; }

[ "$missing" = 0 ] || fail "content check failed for $ZIP"

# An unzipped copy must still carry valid signatures on every xcframework.
mkdir -p "$VERIFY"
unzip -q "$ZIP" -d "$VERIFY"
for name in "${XCFRAMEWORKS[@]}"; do
	codesign --verify --strict "$VERIFY/$ADDON/bin/ios/$name.xcframework" \
		|| fail "$name.xcframework fails codesign --verify --strict after unzipping $ZIP"
done
rm -rf "$VERIFY" "$STAGE"

# Everything passed: publish. Same filesystem, so the move is atomic.
mkdir -p "$ROOT/dist"
mv "$ZIP" "$RELEASE_ZIP"

echo "release: content check ok ($(wc -l <<< "$entries" | tr -d ' ') entries, $zipped_links symlinks)"
echo "release: $RELEASE_ZIP ($(du -h "$RELEASE_ZIP" | awk '{ print $1 }'))"
