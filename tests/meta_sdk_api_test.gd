extends SceneTree

class FakeNative extends Object:
	var calls: Array = []
	func log_event(name: String, params: Dictionary) -> void:
		calls.append([name, params])

## Collects every push_warning text, so the test can check which pairs were reported.
class WarningLog extends Logger:
	var mutex := Mutex.new()
	var warnings: PackedStringArray = []
	func _log_error(_function: String, _file: String, _line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type != ERROR_TYPE_WARNING:
			return
		mutex.lock()
		warnings.append(code + rationale)
		mutex.unlock()
	func _log_message(_message: String, _error: bool) -> void:
		pass
	func take() -> PackedStringArray:
		mutex.lock()
		var result := warnings
		warnings = PackedStringArray()
		mutex.unlock()
		return result

var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ", message)

func warned(warnings: PackedStringArray, text: String) -> bool:
	for warning in warnings:
		if warning.contains(text):
			return true
	return false

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var log := WarningLog.new()
	OS.add_logger(log)

	# Desktop: no singleton. Nothing is forwarded, but dropped pairs still warn.
	MetaSDK.log_event("no_native", {"a": 1, "v": Vector2.ONE, "nan": NAN})
	var warnings := log.take()
	check(warnings.size() == 2, "Without the native singleton each dropped pair still warns once: %s" % " | ".join(warnings))
	check(warned(warnings, "no_native: dropped parameter 'v'"), "Desktop warns about an unsupported value")
	check(warned(warnings, "no_native: dropped parameter 'nan'"), "Desktop warns about a non-finite float")
	MetaSDK.log_event("no_native_clean", {"a": 1})
	check(log.take().is_empty(), "A clean event without the native singleton prints nothing")

	var fake := FakeNative.new()
	Engine.register_singleton("MetaSDKIOS", fake)
	MetaSDK.log_event("fb_mobile_tutorial_completion", {"fb_success": 1})
	check(fake.calls == [["fb_mobile_tutorial_completion", {"fb_success": 1}]], "Name and params reach the native singleton unchanged")
	check(log.take().is_empty(), "Supported params print no warning")
	MetaSDK.log_event("mixed", {"s": "x", &"sn": &"y", "i": 2, "f": 1.5, "b": true,
		"v": Vector2.ONE, "n": null, "arr": [1], "d": {"k": 1}, 7: "int key"})
	check(fake.calls.size() == 2 and fake.calls[1] == ["mixed", {"s": "x", "sn": "y", "i": 2, "f": 1.5, "b": true}],
		"Unsupported values and non-string keys are dropped, the event still goes")
	warnings = log.take()
	check(warnings.size() == 5, "Each dropped pair warns once: %s" % " | ".join(warnings))
	for dropped in ["'v'", "'n'", "'arr'", "'d'", "with non-string key '7'"]:
		check(warned(warnings, "mixed: dropped parameter " + dropped), "The warning names %s" % dropped)

	MetaSDK.log_event("floats", {"nan": NAN, "inf": INF, "-inf": -INF, "zero": 0.0, "neg": -2.5, "big": 1e300})
	check(fake.calls.size() == 3 and fake.calls[2] == ["floats", {"zero": 0.0, "neg": -2.5, "big": 1e300}],
		"NaN and infinities are dropped, finite floats go through")
	warnings = log.take()
	check(warnings.size() == 3, "Each non-finite float warns once: %s" % " | ".join(warnings))
	for dropped in ["nan", "inf", "-inf"]:
		check(warned(warnings, "floats: dropped parameter '%s' with non-finite float" % dropped), "The warning names '%s'" % dropped)

	MetaSDK.log_event("", {"a": 1, "v": Vector2.ONE})
	check(fake.calls.size() == 3, "An empty event name is ignored")
	warnings = log.take()
	check(warnings.size() == 1 and warned(warnings, "empty event name"), "An empty event name warns once and checks no params: %s" % " | ".join(warnings))

	Engine.unregister_singleton("MetaSDKIOS")
	fake.free()
	OS.remove_logger(log)
	if failures == 0:
		print("PASS")
	quit(failures)
