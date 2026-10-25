#!/bin/bash
# Builds the iOS GDExtension: fetches Meta's SDK, compiles the device and
# simulator slices for template_debug and template_release with SCons, wraps
# each dylib as a signed .framework and joins them into a signed .xcframework:
#   addons/meta_sdk/bin/ios/meta_sdk.ios.template_{debug,release}.xcframework
#
# Signing uses the SHA-1 of the first valid "Apple Development: Ozan YILDIZ
# (8F768A29F9)" identity (two identities share that name on the dev Mac);
# set CODESIGN_IDENTITY to override.
set -euo pipefail

cd "$(dirname "$0")/.."
BIN="addons/meta_sdk/bin/ios"
MIN_IOS="15.0"
SIGNING_NAME="Apple Development: Ozan YILDIZ (8F768A29F9)"

fail() { echo "build_ios: $*" >&2; exit 1; }

if [ -z "${CODESIGN_IDENTITY:-}" ]; then
	CODESIGN_IDENTITY="$(security find-identity -v -p codesigning | grep -F "\"$SIGNING_NAME\"" | awk 'NR == 1 { print $2 }')"
	[ -n "$CODESIGN_IDENTITY" ] || fail "no valid \"$SIGNING_NAME\" signing identity (set CODESIGN_IDENTITY)"
fi
echo "build_ios: signing with $CODESIGN_IDENTITY"

if [ ! -x .venv/bin/scons ]; then
	/usr/bin/python3 -m venv .venv
	.venv/bin/pip install --quiet scons==4.9.1
fi

tools/fetch_meta_sdk.sh

# Writes the framework Info.plist (same keys as the Firebase iOS frameworks).
write_info_plist() {
	local plist="$1" name="$2" target="$3" bundle_platform="$4" dt_platform="$5"
	cat > "$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>$name</string>
	<key>CFBundleIdentifier</key>
	<string>com.orebron.metasdk.${target//_/-}</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>$name</string>
	<key>CFBundlePackageType</key>
	<string>FMWK</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0.0</string>
	<key>CFBundleSupportedPlatforms</key>
	<array>
		<string>$bundle_platform</string>
	</array>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>DTPlatformName</key>
	<string>$dt_platform</string>
	<key>MinimumOSVersion</key>
	<string>$MIN_IOS</string>
</dict>
</plist>
PLIST
	plutil -lint -s "$plist" || fail "invalid $plist"
}

for target in template_debug template_release; do
	name="meta_sdk.ios.$target"
	frameworks=()
	for variant in device simulator; do
		if [ "$variant" = "simulator" ]; then
			simulator="yes"; bundle_platform="iPhoneSimulator"; dt_platform="iphonesimulator"
		else
			simulator="no"; bundle_platform="iPhoneOS"; dt_platform="iphoneos"
		fi

		.venv/bin/scons platform=ios arch=arm64 ios_min_version="$MIN_IOS" target="$target" ios_simulator="$simulator"

		out="build/ios/$target/$variant"
		[ -f "$out/$name" ] || fail "scons did not produce $out/$name"
		framework="$out/framework/$name.framework"
		rm -rf "$framework"
		mkdir -p "$framework"
		cp "$out/$name" "$framework/$name"
		write_info_plist "$framework/Info.plist" "$name" "$target" "$bundle_platform" "$dt_platform"
		codesign --force --timestamp=none --sign "$CODESIGN_IDENTITY" "$framework"
		frameworks+=(-framework "$framework")
	done

	xcframework="$BIN/$name.xcframework"
	rm -rf "$xcframework"
	xcodebuild -create-xcframework "${frameworks[@]}" -output "$xcframework"
	codesign --force --timestamp=none --sign "$CODESIGN_IDENTITY" "$xcframework"
	codesign --verify --strict "$xcframework" || fail "$xcframework failed codesign --verify --strict"
	echo "build_ios: $xcframework ok"
done

echo "build_ios: ok"
