#!/bin/bash
# Runs every tests/*_test.gd headless. A test passes when Godot exits with 0 and
# its log contains PASS and has no "SCRIPT ERROR:", "FAIL:" or line starting
# with "ERROR:". A failing test prints its log, or Godot's console output
# (<name>.out, which holds a crash report) when the log is empty.
cd "$(dirname "$0")/.." || exit 1

export TEMP="${TMPDIR:-/tmp}"; export TEMP="${TEMP%/}/meta-sdk-tests"
mkdir -p "$TEMP"

if ! godot --headless --path . --import > "$TEMP/import.log" 2>&1; then
	echo "FAIL import"
	cat "$TEMP/import.log"
	exit 1
fi

failed=0
for test_file in tests/*_test.gd; do
	name="$(basename "$test_file" .gd)"
	log="$TEMP/$name.log"
	out="$TEMP/$name.out"
	rm -f "$log" "$out"
	status=0
	godot --headless --path . --log-file "$log" --script "res://tests/$name.gd" --quit-after 600 > "$out" 2>&1 || status=$?
	if [ "$status" = 0 ] && [ -f "$log" ] && grep -q "PASS" "$log" && ! grep -qE "SCRIPT ERROR:|FAIL:|^ERROR:" "$log"; then
		echo "ok $name"
	else
		echo "FAIL $name (exit $status, console output in $out)"
		if [ -s "$log" ]; then cat "$log"; else cat "$out"; fi
		failed=1
	fi
done

exit $failed
