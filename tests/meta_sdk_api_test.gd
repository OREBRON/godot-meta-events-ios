extends SceneTree

class FakeNative extends Object:
	var calls: Array = []
	func log_event(name: String, params: Dictionary) -> void:
		calls.append([name, params])

var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ", message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	MetaSDK.log_event("no_native", {"a": 1})  # desktop: no singleton, no error
	var fake := FakeNative.new()
	Engine.register_singleton("MetaSDKIOS", fake)
	MetaSDK.log_event("fb_mobile_tutorial_completion", {"fb_success": 1})
	check(fake.calls == [["fb_mobile_tutorial_completion", {"fb_success": 1}]], "Name and params reach the native singleton unchanged")
	MetaSDK.log_event("mixed", {"s": "x", &"sn": &"y", "i": 2, "f": 1.5, "b": true,
		"v": Vector2.ONE, "n": null, "arr": [1], "d": {"k": 1}, 7: "int key"})
	check(fake.calls.size() == 2 and fake.calls[1] == ["mixed", {"s": "x", "sn": "y", "i": 2, "f": 1.5, "b": true}],
		"Unsupported values and non-string keys are dropped, the event still goes")
	MetaSDK.log_event("", {"a": 1})
	check(fake.calls.size() == 2, "An empty event name is ignored")
	Engine.unregister_singleton("MetaSDKIOS")
	fake.free()
	if failures == 0:
		print("PASS")
	quit(failures)
