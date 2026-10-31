class_name MetaSDK
extends RefCounted
## Facade games call to talk to the Meta iOS SDK.
##
## The native side is the Engine singleton "MetaSDKIOS", which only exists in iOS
## builds. On any other platform every call here does nothing.

## Name of the native Engine singleton registered by the iOS GDExtension.
const NATIVE_SINGLETON := "MetaSDKIOS"

## The player's App Tracking Transparency answer: the values of Apple's
## ATTrackingManager.AuthorizationStatus, plus UNAVAILABLE where the native
## singleton is missing (desktop, editor, Android).
enum TrackingStatus { UNAVAILABLE = -1, NOT_DETERMINED = 0, RESTRICTED = 1, DENIED = 2, AUTHORIZED = 3 }


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


## The player's current answer to Apple's tracking prompt. Never shows the prompt.
static func get_tracking_authorization_status() -> TrackingStatus:
	if not Engine.has_singleton(NATIVE_SINGLETON):
		return TrackingStatus.UNAVAILABLE
	return Engine.get_singleton(NATIVE_SINGLETON).get_tracking_authorization_status() as TrackingStatus


## Shows Apple's App Tracking Transparency prompt if the player has not answered
## it yet, then calls `callback` with the TrackingStatus, always deferred. iOS asks
## once per install; later calls report the stored answer without a prompt. The
## prompt waits until the app is active. The Info.plist needs
## NSUserTrackingUsageDescription: without it the call prints an error, shows
## nothing and reports the current status (NOT_DETERMINED unless the player
## answered in an earlier build). Where the native singleton is missing the
## callback gets UNAVAILABLE.
static func request_tracking_authorization(callback: Callable) -> void:
	if not Engine.has_singleton(NATIVE_SINGLETON):
		callback.call_deferred(TrackingStatus.UNAVAILABLE)
		return
	Engine.get_singleton(NATIVE_SINGLETON).request_tracking_authorization(callback)


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
