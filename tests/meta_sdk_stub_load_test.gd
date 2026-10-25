extends SceneTree

var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ", message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	check(GDExtensionManager.is_extension_loaded("res://addons/meta_sdk/meta_sdk.gdextension"), "The desktop stub library loads")
	check(not Engine.has_singleton("MetaSDKIOS"), "The stub registers no native singleton")
	if failures == 0:
		print("PASS")
	quit(failures)
