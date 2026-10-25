@tool
extends EditorPlugin
## Registers the meta_sdk/* project settings and the iOS export plugin.

const Plist = preload("export/meta_sdk_ios_plist.gd")
const IOSExportPlugin = preload("export/meta_sdk_ios_export_plugin.gd")
const SETTINGS := [Plist.APP_ID_SETTING, Plist.CLIENT_TOKEN_SETTING, Plist.DISPLAY_NAME_SETTING]

var _ios_export_plugin: EditorExportPlugin


func _enter_tree() -> void:
	for key: String in SETTINGS:
		if not ProjectSettings.has_setting(key):
			ProjectSettings.set_setting(key, "")
		ProjectSettings.set_initial_value(key, "")
		ProjectSettings.add_property_info({"name": key, "type": TYPE_STRING})
	_ios_export_plugin = IOSExportPlugin.new()
	add_export_plugin(_ios_export_plugin)


func _exit_tree() -> void:
	remove_export_plugin(_ios_export_plugin)
	_ios_export_plugin = null
