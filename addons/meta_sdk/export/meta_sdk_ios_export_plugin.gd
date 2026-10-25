@tool
extends EditorExportPlugin
## Writes the Meta iOS SDK keys into the exported Info.plist.
## The native library and Meta's frameworks are embedded by Godot through the
## .gdextension file; _export_end then replaces Godot's copies of Meta's
## frameworks with exact ones so their signatures still verify in Xcode.

const Plist = preload("meta_sdk_ios_plist.gd")
const Frameworks = preload("meta_sdk_ios_frameworks.gd")

## Where this iOS export's Meta frameworks land; empty for other exports.
var _exported_frameworks_dir := ""


func _get_name() -> String:
	return "MetaSDKIOS"


func _supports_platform(platform: EditorExportPlatform) -> bool:
	return platform is EditorExportPlatformIOS


func _get_export_options(_platform: EditorExportPlatform) -> Array[Dictionary]:
	return [{"option": {"name": Plist.SKADNETWORK_OPTION, "type": TYPE_BOOL}, "default_value": true}]


func _get_export_option_warning(_platform: EditorExportPlatform, option: String) -> String:
	if option != Plist.SKADNETWORK_OPTION:
		return ""
	var add_skadnetwork: bool = get_option(option)
	var result := _build_plist(add_skadnetwork)
	if result.error != OK:
		return result.message
	var enabled_plugins: PackedStringArray = ProjectSettings.get_setting("editor_plugins/enabled", PackedStringArray())
	return Plist.skadnetwork_warning(add_skadnetwork, enabled_plugins)


## Without a valid App ID the Info.plist gets no Meta keys. The native side then
## skips SDK start-up, so the app still runs; it only measures nothing.
func _export_begin(features: PackedStringArray, _is_debug: bool, path: String, _flags: int) -> void:
	_exported_frameworks_dir = ""
	if not features.has("ios"):
		return
	_exported_frameworks_dir = Frameworks.exported_dir(path)
	var add_skadnetwork: bool = get_option(Plist.SKADNETWORK_OPTION)
	var result := _build_plist(add_skadnetwork)
	if result.error != OK:
		push_error("Meta SDK iOS configuration error: " + result.message)
		return
	add_apple_embedded_platform_plist_content(result.content)


## Godot calls this once the Xcode project is written. A one-click export
## (application/export_project_only off) runs xcodebuild before that, so only
## project-only exports reach Xcode with the exact frameworks.
func _export_end() -> void:
	if _exported_frameworks_dir.is_empty():
		return
	for message in Frameworks.restore(_exported_frameworks_dir):
		push_error("Meta SDK iOS export error: " + message)
	_exported_frameworks_dir = ""


func _build_plist(add_skadnetwork: bool) -> Dictionary:
	var display_name := _string_setting(Plist.DISPLAY_NAME_SETTING)
	if display_name.is_empty():
		display_name = _string_setting("application/config/name")
	return Plist.plist(_string_setting(Plist.APP_ID_SETTING), _string_setting(Plist.CLIENT_TOKEN_SETTING), display_name, add_skadnetwork)


## A missing or non-String setting reads as empty instead of "<null>".
func _string_setting(setting: String) -> String:
	var value: Variant = get_export_preset().get_project_setting(setting)
	return value if value is String else ""
