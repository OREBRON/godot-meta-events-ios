extends SceneTree

const Frameworks = preload("res://addons/meta_sdk/export/meta_sdk_ios_frameworks.gd")

var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ", message)

func write_file(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()

## A versioned framework bundle like the Mac Catalyst slices in Meta's
## xcframeworks: real files under Versions/A plus relative symlinks to them.
func make_signed_layout(xcframework: String) -> void:
	write_file(xcframework.path_join("Info.plist"), "plist")
	var bundle := xcframework.path_join("maccatalyst/Kit.framework")
	write_file(bundle.path_join("Versions/A/Kit"), "binary")
	FileAccess.set_unix_permissions(bundle.path_join("Versions/A/Kit"), 0b111_101_101)
	write_file(bundle.path_join("Versions/A/Headers/Kit.h"), "header")
	var dir := DirAccess.open(bundle)
	dir.create_link("A", bundle.path_join("Versions/Current"))
	dir.create_link("Versions/Current/Kit", bundle.path_join("Kit"))
	dir.create_link("Versions/Current/Headers", bundle.path_join("Headers"))

## What Godot's export leaves behind: the same names, symlinks turned into copies.
func make_godot_copy(xcframework: String) -> void:
	write_file(xcframework.path_join("Info.plist"), "plist")
	var bundle := xcframework.path_join("maccatalyst/Kit.framework")
	for path in ["Versions/A/Kit", "Versions/Current/Kit", "Kit"]:
		write_file(bundle.path_join(path), "binary")
	for path in ["Versions/A/Headers/Kit.h", "Versions/Current/Headers/Kit.h", "Headers/Kit.h"]:
		write_file(bundle.path_join(path), "header")

func link_target(path: String) -> String:
	var dir := DirAccess.open(path.get_base_dir())
	if dir == null or not dir.is_link(path.get_file()):
		return "<not a link>"
	return dir.read_link(path.get_file())

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var project := ProjectSettings.globalize_path("res://")
	check(Frameworks.exported_dir("build/ios/MetaSDKDemo.xcodeproj") == project.path_join("build/ios/MetaSDKDemo/dylibs/addons/meta_sdk/bin/ios"), "Relative export paths resolve against the project")
	check(Frameworks.exported_dir("/Users/dev/out/Color Sprint.xcodeproj") == "/Users/dev/out/Color Sprint/dylibs/addons/meta_sdk/bin/ios", "Absolute export paths keep their folder")

	var root := OS.get_temp_dir().path_join("meta_sdk_frameworks_test")
	if DirAccess.dir_exists_absolute(root):
		check(Frameworks.remove_tree(root) == OK, "Old test folder removed")
	var source := root.path_join("source")
	var exported := root.path_join("exported")
	for name in Frameworks.NAMES:
		make_signed_layout(source.path_join(name + ".xcframework"))
		make_godot_copy(exported.path_join(name + ".xcframework"))
	write_file(exported.path_join("meta_sdk.ios.template_debug.xcframework/Info.plist"), "ours")

	var errors := Frameworks.restore(exported, source)
	check(errors.is_empty(), "Restore reports no errors: %s" % ", ".join(errors))
	for name in Frameworks.NAMES:
		var bundle := exported.path_join(name + ".xcframework/maccatalyst/Kit.framework")
		check(link_target(bundle.path_join("Versions/Current")) == "A", "%s: Versions/Current is the original symlink" % name)
		check(link_target(bundle.path_join("Kit")) == "Versions/Current/Kit", "%s: the binary symlink is kept" % name)
		check(link_target(bundle.path_join("Headers")) == "Versions/Current/Headers", "%s: the Headers symlink is kept" % name)
		check(FileAccess.get_file_as_string(bundle.path_join("Versions/A/Kit")) == "binary", "%s: real files are copied" % name)
		check((FileAccess.get_unix_permissions(bundle.path_join("Versions/A/Kit")) & 0b111_111_111) == 0b111_101_101, "%s: file permissions are kept" % name)
		check(FileAccess.get_file_as_string(exported.path_join(name + ".xcframework/Info.plist")) == "plist", "%s: top-level files are copied" % name)
	check(FileAccess.get_file_as_string(exported.path_join("meta_sdk.ios.template_debug.xcframework/Info.plist")) == "ours", "Other exported frameworks are left alone")
	check(FileAccess.get_file_as_string(source.path_join("FBAEMKit.xcframework/maccatalyst/Kit.framework/Versions/A/Kit")) == "binary", "The originals are untouched")

	Frameworks.remove_tree(exported.path_join("FBAEMKit.xcframework"))
	errors = Frameworks.restore(exported, source)
	check(errors.size() == 1 and errors[0].contains("FBAEMKit.xcframework"), "A framework Godot did not export is reported: %s" % ", ".join(errors))

	check(Frameworks.remove_tree(root) == OK and not DirAccess.dir_exists_absolute(root), "remove_tree deletes a tree with symlinks")
	if failures == 0:
		print("PASS")
	quit(failures)
