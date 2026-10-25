@tool
extends RefCounted
## Puts exact copies of Meta's xcframeworks into an exported iOS Xcode project.
##
## Godot embeds the .gdextension [dependencies] by copying them to
## <export dir>/<Name>/dylibs/addons/meta_sdk/bin/ios/, but it copies symlinks as
## plain files and folders. Meta's Mac Catalyst slices are versioned bundles full
## of symlinks, so those copies no longer match Meta's signature and Xcode stops
## the build: "The signature of “FBSDKCoreKit.xcframework” cannot be verified."

const SOURCE_DIR := "res://addons/meta_sdk/bin/ios"
const NAMES: Array[String] = ["FBSDKCoreKit", "FBSDKCoreKit_Basics", "FBAEMKit"]


## The folder Godot copies SOURCE_DIR's frameworks to for an iOS export to
## export_path (".../<Name>.xcodeproj"). Relative paths are project-relative,
## as Godot treats them.
static func exported_dir(export_path: String) -> String:
	if export_path.is_relative_path():
		export_path = "res://" + export_path
	export_path = ProjectSettings.globalize_path(export_path)
	var binary_name := export_path.get_file().get_basename()
	return export_path.get_base_dir().path_join(binary_name).path_join("dylibs").path_join(SOURCE_DIR.trim_prefix("res://"))


## Replaces Godot's copy of each Meta xcframework in target_dir with an exact copy
## of the original in source_dir, symlinks included. Returns one message per failure.
static func restore(target_dir: String, source_dir: String = SOURCE_DIR) -> PackedStringArray:
	var errors := PackedStringArray()
	for name in NAMES:
		var source := ProjectSettings.globalize_path(source_dir).path_join(name + ".xcframework")
		var target := target_dir.path_join(name + ".xcframework")
		if not DirAccess.dir_exists_absolute(target):
			errors.append("%s.xcframework was not exported to %s" % [name, target_dir])
			continue
		var err := remove_tree(target)
		if err == OK:
			err = copy_tree(source, target)
		if err != OK:
			errors.append("could not copy %s to %s: %s" % [source, target, error_string(err)])
	return errors


## Copies a folder tree; symlinks stay symlinks and files keep their permissions.
static func copy_tree(from: String, to: String) -> Error:
	var dir := DirAccess.open(from)
	if dir == null:
		return DirAccess.get_open_error()
	var err := DirAccess.make_dir_recursive_absolute(to)
	for entry in _entries(dir):
		if err != OK:
			break
		var source := from.path_join(entry)
		var target := to.path_join(entry)
		if dir.is_link(entry):
			err = dir.create_link(dir.read_link(entry), target)
		elif dir.dir_exists(entry):
			err = copy_tree(source, target)
		else:
			err = dir.copy(source, target, FileAccess.get_unix_permissions(source))
	return err


## Deletes a folder tree without following symlinks out of it.
static func remove_tree(path: String) -> Error:
	var dir := DirAccess.open(path)
	if dir == null:
		return DirAccess.get_open_error()
	var err := OK
	for entry in _entries(dir):
		if err != OK:
			break
		if dir.dir_exists(entry) and not dir.is_link(entry):
			err = remove_tree(path.path_join(entry))
		else:
			err = dir.remove(entry)
	return err if err != OK else DirAccess.remove_absolute(path)


## Every entry of dir, hidden ones included, listed before anything changes.
static func _entries(dir: DirAccess) -> PackedStringArray:
	dir.include_hidden = true
	dir.include_navigational = false
	var entries := PackedStringArray()
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		entries.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	return entries
