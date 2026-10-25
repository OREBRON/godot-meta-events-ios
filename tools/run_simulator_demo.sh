#!/bin/bash
# Exports the demo project (res://demo/demo.tscn) for iOS, builds it for the
# iOS Simulator, runs it on the first available iPhone simulator for 20 s and
# keeps everything it printed:
#   tools/run_simulator_demo.sh [out_dir]      (default: build/ios)
# Writes <out>/export.log, <out>/xcodebuild.log and <out>/console.log (the
# app's console followed by its unified log lines), and exits 1 when the app
# was no longer running after 20 s.
# Needs the iOS binaries from tools/build_ios.sh in addons/meta_sdk/bin/ios.
set -euo pipefail

cd "$(dirname "$0")/.."
OUT="${1:-build/ios}"
NAME="MetaSDKDemo"
BUNDLE_ID="com.orebron.metasdkdemo"
RUN_SECONDS=20

fail() { echo "run_simulator_demo: $*" >&2; exit 1; }

mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
# Only this script's outputs: build/ios also holds tools/build_ios.sh's SCons output.
rm -rf "$OUT/$NAME" "$OUT/$NAME.xcodeproj" "$OUT/$NAME.xcframework" "$OUT/$NAME.pck" "$OUT/dd" \
	"$OUT/export.log" "$OUT/xcodebuild.log" "$OUT/console.log"

echo "run_simulator_demo: exporting $OUT/$NAME.xcodeproj"
godot --headless --path . --export-debug iOS "$OUT/$NAME.xcodeproj" > "$OUT/export.log" 2>&1 \
	|| { cat "$OUT/export.log"; fail "godot export failed"; }
cat "$OUT/export.log"
[ -d "$OUT/$NAME.xcodeproj" ] || fail "godot did not write $OUT/$NAME.xcodeproj"

# Godot 4.7.2's official iOS template ships an x86_64-only simulator libgodot.a,
# but the iOS 27 Simulator runs arm64 only. Add an arm64 simulator slice made
# from the device slice (tools/retag_ios_simulator.py), plus the two Metal
# constants the device code uses that the Simulator's Metal does not export.
# The addon's own binaries and Meta's frameworks are used as built.
godot_xcframework="$OUT/$NAME.xcframework"
simulator_lib="$godot_xcframework/ios-arm64_x86_64-simulator/libgodot.a"
if ! lipo "$simulator_lib" -verify_arch arm64 2> /dev/null; then
	echo "run_simulator_demo: adding an arm64 slice to the simulator libgodot.a"
	work="$OUT/simulator-libgodot"
	rm -rf "$work"
	mkdir -p "$work"
	/usr/bin/python3 -I tools/retag_ios_simulator.py "$godot_xcframework/ios-arm64/libgodot.a" "$work/libgodot.arm64.a"
	cat > "$work/metal_constants.m" <<'OBJC'
#import <Foundation/Foundation.h>
NSString *const MTLIOErrorDomain = @"MTLIOErrorDomain";
NSString *const MTLTensorDomain = @"MTLTensorDomain";
OBJC
	xcrun -sdk iphonesimulator clang -arch arm64 -mios-simulator-version-min=15.0 -fobjc-arc \
		-c "$work/metal_constants.m" -o "$work/metal_constants.o"
	ar -rs "$work/libgodot.arm64.a" "$work/metal_constants.o"
	lipo -create "$simulator_lib" "$work/libgodot.arm64.a" -output "$work/libgodot.a"
	mv "$work/libgodot.a" "$simulator_lib"
	rm -rf "$work"
fi

scheme="$(xcodebuild -list -json -project "$OUT/$NAME.xcodeproj" | plutil -extract project.schemes.0 raw -o - -)" \
	|| fail "no scheme in $OUT/$NAME.xcodeproj"
echo "run_simulator_demo: building scheme $scheme"
xcodebuild -project "$OUT/$NAME.xcodeproj" -scheme "$scheme" -sdk iphonesimulator \
	-destination 'generic/platform=iOS Simulator' -derivedDataPath "$OUT/dd" \
	CODE_SIGNING_ALLOWED=NO build > "$OUT/xcodebuild.log" 2>&1 \
	|| { tail -n 40 "$OUT/xcodebuild.log"; fail "xcodebuild failed; see $OUT/xcodebuild.log"; }
app="$OUT/dd/Build/Products/Debug-iphonesimulator/$NAME.app"
[ -d "$app" ] || fail "xcodebuild did not produce $app"

udid="$(xcrun simctl list devices available --json | /usr/bin/python3 -c '
import json, sys
for runtime, devices in json.load(sys.stdin)["devices"].items():
    if "iOS" not in runtime:
        continue
    for device in devices:
        if device["name"].startswith("iPhone"):
            print(device["udid"])
            sys.exit(0)
')" || fail "could not list simulators"
[ -n "$udid" ] || fail "no available iPhone simulator"
echo "run_simulator_demo: simulator $udid"

if ! boot_output="$(xcrun simctl boot "$udid" 2>&1)"; then
	case "$boot_output" in
		*"current state: Booted"*) ;;
		*) echo "$boot_output" >&2; fail "could not boot $udid" ;;
	esac
fi
xcrun simctl bootstatus "$udid" > /dev/null
xcrun simctl install "$udid" "$app"

launch_time="$(date '+%Y-%m-%d %H:%M:%S')"
xcrun simctl launch --console-pty --terminate-running-process "$udid" "$BUNDLE_ID" > "$OUT/console.log" 2>&1 &
launch_pid=$!
sleep "$RUN_SECONDS"

# A running app shows up as "<pid> <status> UIKitApplication:<bundle id>[...]".
job="$(xcrun simctl spawn "$udid" launchctl list | grep "$BUNDLE_ID" || true)"
if [ -n "$job" ] && [[ "$(awk '{ print $1 }' <<< "$job")" =~ ^[0-9]+$ ]]; then
	running="yes"
else
	running="no"
fi

xcrun simctl terminate "$udid" "$BUNDLE_ID" > /dev/null 2>&1 || true
kill "$launch_pid" > /dev/null 2>&1 || true
wait "$launch_pid" 2> /dev/null || true

# Meta's FBSDKLog lines reach the console, but Godot prints (print, push_error,
# ERR_PRINT) only to the unified log, at info level for print. Add this run's
# lines; --start rather than --last keeps earlier runs out.
{
	echo "--- log show --info --start \"$launch_time\" (process == \"$NAME\") ---"
	xcrun simctl spawn "$udid" log show --info --start "$launch_time" --predicate "process == \"$NAME\""
} >> "$OUT/console.log" 2>&1 || true

echo "run_simulator_demo: launchctl: ${job:-<no job>}"
echo "run_simulator_demo: app running after ${RUN_SECONDS} s: $running"
echo "run_simulator_demo: console log $OUT/console.log"
[ "$running" = "yes" ] || fail "the app was not running after ${RUN_SECONDS} s"
