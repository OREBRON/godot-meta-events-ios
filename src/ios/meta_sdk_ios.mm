#include "meta_sdk_ios.h"

#include <godot_cpp/core/error_macros.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <godot_cpp/variant/variant.hpp>

#import <AppTrackingTransparency/AppTrackingTransparency.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// FBSDKCoreKit-Swift.h only @imports its dependencies when Objective-C modules
// are on, so import them explicitly for this non-modular Objective-C++ build.
#import <AuthenticationServices/AuthenticationServices.h>
#import <SafariServices/SafariServices.h>
#import <StoreKit/StoreKit.h>
#import <FBAEMKit/FBAEMKit-Swift.h>
#import <FBSDKCoreKit_Basics/FBSDKCoreKit_Basics.h>
#import <FBSDKCoreKit/FBSDKCoreKit.h>
// FBSDKApplicationDelegate and FBSDKSettings are Swift classes.
#import <FBSDKCoreKit/FBSDKCoreKit-Swift.h>

using namespace godot;

static NSString *to_ns_string(const String &p_string) {
	NSString *result = [NSString stringWithUTF8String:p_string.utf8().get_data()];
	return result != nil ? result : @"";
}

static bool info_plist_has_string(NSString *p_key) {
	id value = [NSBundle.mainBundle objectForInfoDictionaryKey:p_key];
	return [value isKindOfClass:NSString.class] && ((NSString *)value).length > 0;
}

void MetaSDKIOS::_bind_methods() {
	ClassDB::bind_method(D_METHOD("log_event", "name", "params"), &MetaSDKIOS::log_event);
	ClassDB::bind_method(D_METHOD("get_tracking_authorization_status"), &MetaSDKIOS::get_tracking_authorization_status);
	ClassDB::bind_method(D_METHOD("request_tracking_authorization", "callback"), &MetaSDKIOS::request_tracking_authorization);
}

void MetaSDKIOS::start() {
	if (started) {
		return;
	}
	// Meta's SDK can crash the app when it starts without an App ID or a client
	// token (FBSDKCoreKit raises InvalidOperationException for the latter), so
	// check both before any FBSDK call.
	if (!info_plist_has_string(@"FacebookAppID")) {
		ERR_PRINT("MetaSDK: FacebookAppID is missing from Info.plist; Meta SDK not started.");
		return;
	}
	if (!info_plist_has_string(@"FacebookClientToken")) {
		ERR_PRINT("MetaSDK: FacebookClientToken is missing from Info.plist; Meta SDK not started.");
		return;
	}

#ifdef DEBUG_ENABLED
	[FBSDKSettings.sharedSettings enableLoggingBehavior:FBSDKLoggingBehaviorAppEvents];
#endif

	void (^launch)(void) = ^{
		[FBSDKApplicationDelegate.sharedInstance application:UIApplication.sharedApplication didFinishLaunchingWithOptions:nil];
		started = true;
#ifdef DEBUG_ENABLED
		UtilityFunctions::print("MetaSDK: started");
#endif
	};
	if (NSThread.isMainThread) {
		launch();
	} else {
		dispatch_async(dispatch_get_main_queue(), launch);
	}
}

void MetaSDKIOS::log_event(const String &p_name, const Dictionary &p_params) {
	if (!started) {
		return;
	}

	NSMutableDictionary<NSString *, id> *parameters = [NSMutableDictionary dictionaryWithCapacity:(NSUInteger)p_params.size()];
	const Array keys = p_params.keys();
	for (int64_t i = 0; i < keys.size(); i++) {
		const Variant key = keys[i];
		if (key.get_type() != Variant::STRING && key.get_type() != Variant::STRING_NAME) {
			continue;
		}
		const Variant value = p_params[key];
		id ns_value = nil;
		switch (value.get_type()) {
			case Variant::STRING:
			case Variant::STRING_NAME:
				ns_value = to_ns_string(value);
				break;
			case Variant::INT:
				ns_value = @((long long)value);
				break;
			case Variant::FLOAT:
				ns_value = @((double)value);
				break;
			case Variant::BOOL:
				ns_value = @((BOOL)(bool)value);
				break;
			default:
				break;
		}
		if (ns_value != nil) {
			parameters[to_ns_string(key)] = ns_value;
		}
	}

	[FBSDKAppEvents.shared logEvent:to_ns_string(p_name) parameters:parameters];
#ifdef DEBUG_ENABLED
	UtilityFunctions::print("MetaSDK: logged ", p_name);
#endif
}

int64_t MetaSDKIOS::get_tracking_authorization_status() const {
	return (int64_t)ATTrackingManager.trackingAuthorizationStatus;
}

void MetaSDKIOS::request_tracking_authorization(const Callable &p_callback) {
	// iOS terminates an app that asks for tracking without a purpose string.
	if (!info_plist_has_string(@"NSUserTrackingUsageDescription")) {
		ERR_PRINT("MetaSDK: NSUserTrackingUsageDescription is missing from Info.plist; tracking prompt not shown.");
		p_callback.call_deferred(get_tracking_authorization_status());
		return;
	}
	// iOS asks once per install; afterwards only Settings can change the answer.
	if (ATTrackingManager.trackingAuthorizationStatus != ATTrackingManagerAuthorizationStatusNotDetermined) {
		p_callback.call_deferred(get_tracking_authorization_status());
		return;
	}

	const Callable callback = p_callback;
	void (^request)(void) = ^{
		[ATTrackingManager requestTrackingAuthorizationWithCompletionHandler:^(ATTrackingManagerAuthorizationStatus status) {
			// The completion handler runs on a background queue.
			dispatch_async(dispatch_get_main_queue(), ^{
#ifdef DEBUG_ENABLED
				UtilityFunctions::print("MetaSDK: tracking authorization ", (int64_t)status);
#endif
				callback.call_deferred((int64_t)status);
			});
		}];
	};
	// iOS shows the prompt only while the app is active; asked during launch or
	// from the background it answers "not determined" without showing it.
	void (^request_when_active)(void) = ^{
		if (UIApplication.sharedApplication.applicationState == UIApplicationStateActive) {
			request();
			return;
		}
		__block id observer = [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification
																			  object:nil
																			   queue:NSOperationQueue.mainQueue
																		  usingBlock:^(NSNotification *) {
																			  [NSNotificationCenter.defaultCenter removeObserver:observer];
																			  observer = nil;
																			  request();
																		  }];
	};
	if (NSThread.isMainThread) {
		request_when_active();
	} else {
		dispatch_async(dispatch_get_main_queue(), request_when_active);
	}
}
