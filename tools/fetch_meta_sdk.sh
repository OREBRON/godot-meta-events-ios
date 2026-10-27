#!/bin/bash
# Downloads Meta's iOS SDK v19.0.0 dynamic XCFrameworks (FBSDKCoreKit,
# FBSDKCoreKit_Basics, FBAEMKit) into vendor/, checks each zip's SHA-256 and
# copies the unmodified, Meta-signed xcframeworks into addons/meta_sdk/bin/ios/.
# A zip is downloaded only when it is missing or its checksum differs.
set -euo pipefail

cd "$(dirname "$0")/.."
VERSION="19.0.0"
VENDOR="vendor/meta-sdk-$VERSION"
BIN="addons/meta_sdk/bin/ios"
BASE_URL="https://github.com/facebook/facebook-ios-sdk/releases/download/v$VERSION"

# <Name>:<sha256 of <Name>-Dynamic_XCFramework.zip>
FRAMEWORKS=(
	"FBSDKCoreKit:791756b0786b79909de375d7060304d7822edac738218863f07470b1acfcde76"
	"FBSDKCoreKit_Basics:7cdfe6a706a4852854aac2dcb24b4aa48ad231f1a3655605ea2333b6d0e2b305"
	"FBAEMKit:df494f1e8130d975a0dfbfd54d1471c63d86767589bf03b98f6631ad87feb2ad"
)

fail() { echo "fetch_meta_sdk: $*" >&2; exit 1; }

sha256_of() { shasum -a 256 "$1" | awk '{ print $1 }'; }

mkdir -p "$VENDOR" "$BIN"

for pair in "${FRAMEWORKS[@]}"; do
	name="${pair%%:*}"
	expected="${pair#*:}"
	zip="$VENDOR/$name-Dynamic_XCFramework.zip"

	if [ -f "$zip" ] && [ "$(sha256_of "$zip")" = "$expected" ]; then
		echo "fetch_meta_sdk: $name zip already present"
	else
		echo "fetch_meta_sdk: downloading $name"
		rm -f "$zip" "$zip.part"
		curl -fsSL --retry 3 -o "$zip.part" "$BASE_URL/$name-Dynamic_XCFramework.zip"
		actual="$(sha256_of "$zip.part")"
		if [ "$actual" != "$expected" ]; then
			rm -f "$zip.part"
			fail "$name checksum mismatch: expected $expected, got $actual"
		fi
		mv "$zip.part" "$zip"
	fi

	# Unzip each archive into its own fresh folder so stale files never linger.
	rm -rf "${VENDOR:?}/$name"
	unzip -q "$zip" -d "$VENDOR/$name"

	matches="$(find "$VENDOR" -maxdepth 3 -type d -name "$name.xcframework")"
	[ -n "$matches" ] || fail "$name.xcframework not found in $zip"
	[ "$(printf '%s\n' "$matches" | wc -l | tr -d ' ')" = "1" ] || fail "more than one $name.xcframework under $VENDOR: $matches"

	rm -rf "${BIN:?}/$name.xcframework"
	ditto "$matches" "$BIN/$name.xcframework"
	codesign --verify --strict "$BIN/$name.xcframework" || fail "$BIN/$name.xcframework failed codesign --verify --strict"
	echo "fetch_meta_sdk: $BIN/$name.xcframework ok"
done
