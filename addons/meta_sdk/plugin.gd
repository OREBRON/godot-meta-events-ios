@tool
extends EditorPlugin
## Registers the meta_sdk/* project settings and the iOS export plugin.

const Plist = preload("export/meta_sdk_ios_plist.gd")
const IOSExportPlugin = preload("export/meta_sdk_ios_export_plugin.gd")
const SETTINGS := [Plist.APP_ID_SETTING, Plist.CLIENT_TOKEN_SETTING, Plist.DISPLAY_NAME_SETTING]
## Keeps bin/ios (Meta's 26 *.abi.json files, about 53 MB) out of exported game data.
const BIN_IOS_DIR := "res://addons/meta_sdk/bin/ios"

var _ios_export_plugin: EditorExportPlugin


func _enter_tree() -> void:
	for key: String in SETTINGS:
		if not ProjectSettings.has_setting(key):
			ProjectSettings.set_setting(key, "")
		ProjectSettings.set_initial_value(key, "")
		ProjectSettings.add_property_info({"name": key, "type": TYPE_STRING})
		# Shown in Project Settings without the "Advanced Settings" toggle.
		ProjectSettings.set_as_basic(key, true)
	_warn_if_gdignore_missing()
	_ios_export_plugin = IOSExportPlugin.new()
	add_export_plugin(_ios_export_plugin)


func _exit_tree() -> void:
	remove_export_plugin(_ios_export_plugin)
	_ios_export_plugin = null


## The release zip ships bin/ios/.gdignore, but a copy that skips dotfiles drops
## it; every export with "Export all resources" then packs Meta's *.abi.json files.
func _warn_if_gdignore_missing() -> void:
	if DirAccess.dir_exists_absolute(BIN_IOS_DIR) and not FileAccess.file_exists(BIN_IOS_DIR.path_join(".gdignore")):
		push_warning("Meta SDK: %s/.gdignore is missing, so exports pack Meta's *.abi.json files (about 53 MB) into the game data. Fix: delete addons/meta_sdk and extract the release zip again with a tool that keeps dotfiles and symlinks (unzip or ditto -xk)." % BIN_IOS_DIR)
