#include "register_types.h"

#include "meta_sdk_ios.h"

#include <gdextension_interface.h>
#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/core/memory.hpp>
#include <godot_cpp/godot.hpp>

using namespace godot;

static const char *SINGLETON_NAME = "MetaSDKIOS";
static MetaSDKIOS *meta_sdk_ios = nullptr;

void initialize_meta_sdk_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_CLASS(MetaSDKIOS);
	meta_sdk_ios = memnew(MetaSDKIOS);
	Engine::get_singleton()->register_singleton(SINGLETON_NAME, meta_sdk_ios);
	meta_sdk_ios->start();
}

void uninitialize_meta_sdk_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE || meta_sdk_ios == nullptr) {
		return;
	}
	Engine::get_singleton()->unregister_singleton(SINGLETON_NAME);
	memdelete(meta_sdk_ios);
	meta_sdk_ios = nullptr;
}

extern "C" {
GDExtensionBool GDE_EXPORT meta_sdk_library_init(GDExtensionInterfaceGetProcAddress p_get_proc_address, const GDExtensionClassLibraryPtr p_library, GDExtensionInitialization *r_initialization) {
	GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);
	init_obj.register_initializer(initialize_meta_sdk_module);
	init_obj.register_terminator(uninitialize_meta_sdk_module);
	init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
	return init_obj.init();
}
}
