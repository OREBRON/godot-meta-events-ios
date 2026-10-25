class_name MetaSDK
extends RefCounted
## Facade games call to talk to the Meta iOS SDK.
##
## The native side is the Engine singleton "MetaSDKIOS", which only exists in iOS
## builds. On any other platform every call here does nothing.

## Name of the native Engine singleton registered by the iOS GDExtension.
const NATIVE_SINGLETON := "MetaSDKIOS"


## Logs an app event to Meta. Does nothing when the native singleton is missing
## (desktop, editor). Parameter pairs Meta cannot take are dropped with a warning
## and the event is still sent: keys must be String or StringName, values must be
## String, StringName, int, finite float or bool. The parameters are checked on
## every platform, so desktop runs print the same warnings an iOS build would.
static func log_event(name: String, params: Dictionary = {}) -> void:
	if name.is_empty():
		push_warning("MetaSDK: log_event called with an empty event name; ignored.")
		return
	var clean := _sanitize(name, params)
	if not Engine.has_singleton(NATIVE_SINGLETON):
		return
	var native := Engine.get_singleton(NATIVE_SINGLETON)
	native.log_event(name, clean)


static func _sanitize(event_name: String, params: Dictionary) -> Dictionary:
	var clean := {}
	for key: Variant in params:
		var value: Variant = params[key]
		if typeof(key) != TYPE_STRING and typeof(key) != TYPE_STRING_NAME:
			push_warning("MetaSDK: %s: dropped parameter with non-string key '%s'." % [event_name, str(key)])
			continue
		match typeof(value):
			TYPE_STRING, TYPE_STRING_NAME:
				clean[String(key)] = String(value)
			TYPE_INT, TYPE_BOOL:
				clean[String(key)] = value
			TYPE_FLOAT:
				# NaN and infinities have no JSON form; Meta's SDK cannot send them.
				if is_finite(value):
					clean[String(key)] = value
				else:
					push_warning("MetaSDK: %s: dropped parameter '%s' with non-finite float %s." % [event_name, String(key), str(value)])
			_:
				push_warning("MetaSDK: %s: dropped parameter '%s' with unsupported value type %s." % [event_name, String(key), type_string(typeof(value))])
	return clean
