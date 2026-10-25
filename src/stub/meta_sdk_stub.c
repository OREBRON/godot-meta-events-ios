// No-op GDExtension for every platform except iOS. It registers no class or
// singleton; its only job is to keep Godot from reporting a missing library
// for meta_sdk.gdextension on desktop and Android.
#include "../../godot-cpp/gdextension/gdextension_interface.h"

#ifdef _WIN32
#define META_SDK_EXPORT __declspec(dllexport)
#else
#define META_SDK_EXPORT __attribute__((visibility("default")))
#endif

static void meta_sdk_stub_initialize(void *p_userdata, GDExtensionInitializationLevel p_level) {
	(void)p_userdata;
	(void)p_level;
}

static void meta_sdk_stub_deinitialize(void *p_userdata, GDExtensionInitializationLevel p_level) {
	(void)p_userdata;
	(void)p_level;
}

META_SDK_EXPORT GDExtensionBool meta_sdk_library_init(GDExtensionInterfaceGetProcAddress p_get_proc_address, GDExtensionClassLibraryPtr p_library, GDExtensionInitialization *r_initialization) {
	(void)p_get_proc_address;
	(void)p_library;
	r_initialization->minimum_initialization_level = GDEXTENSION_INITIALIZATION_SCENE;
	r_initialization->userdata = NULL;
	r_initialization->initialize = meta_sdk_stub_initialize;
	r_initialization->deinitialize = meta_sdk_stub_deinitialize;
	return 1;
}
