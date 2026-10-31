#pragma once

#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/callable.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>

#include <atomic>

// Engine singleton "MetaSDKIOS": starts Meta's iOS SDK when the extension loads,
// forwards MetaSDK.log_event calls to FBSDKAppEvents and asks for App Tracking
// Transparency (ATT) permission.
class MetaSDKIOS : public godot::Object {
	GDCLASS(MetaSDKIOS, godot::Object);

	std::atomic<bool> started{ false };

protected:
	static void _bind_methods();

public:
	// Starts the SDK when Info.plist has a FacebookAppID; otherwise prints one
	// error and leaves the SDK off. Not bound: register_types.cpp calls it.
	void start();
	void log_event(const godot::String &p_name, const godot::Dictionary &p_params);

	// Apple's ATTrackingManagerAuthorizationStatus: 0 not determined,
	// 1 restricted, 2 denied, 3 authorized. Works whether or not start() ran.
	int64_t get_tracking_authorization_status() const;
	// Shows Apple's tracking prompt if the player has not answered it, then
	// calls p_callback deferred on the main thread with the resulting status.
	void request_tracking_authorization(const godot::Callable &p_callback);
};
