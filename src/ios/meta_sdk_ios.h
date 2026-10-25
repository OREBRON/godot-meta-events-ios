#pragma once

#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>

#include <atomic>

// Engine singleton "MetaSDKIOS": starts Meta's iOS SDK when the extension loads
// and forwards MetaSDK.log_event calls to FBSDKAppEvents.
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
};
