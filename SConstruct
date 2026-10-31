#!/usr/bin/env python
# Builds the iOS GDExtension (MetaSDKIOS) for one target and one slice:
#   scons platform=ios arch=arm64 ios_min_version=15.0 target=template_debug ios_simulator=no
# Output: build/ios/<target>/<device|simulator>/meta_sdk.ios.<target>, a bare
# dylib that tools/build_ios.sh wraps into a .framework and an .xcframework.
# Other platforms load the no-op stubs from tools/build_stubs.sh instead.
import os
import plistlib

# Keep SCons' signature database out of the repository root.
os.makedirs("build", exist_ok=True)
SConsignFile("build/.sconsign")

env = SConscript("godot-cpp/SConstruct")

if env["platform"] != "ios":
    print("SConstruct: only platform=ios is built here; run tools/build_stubs.sh for the stub libraries.")
    Exit(1)

META_BIN = "addons/meta_sdk/bin/ios"
META_FRAMEWORKS = ["FBSDKCoreKit", "FBSDKCoreKit_Basics", "FBAEMKit"]

target = env["target"]
variant = "simulator" if env["ios_simulator"] else "device"
name = "meta_sdk.ios." + target
out_dir = "build/ios/{}/{}".format(target, variant)


def meta_slice(framework):
    """Path of the xcframework slice for this platform variant and arch, read from its Info.plist."""
    xcframework = os.path.join(META_BIN, framework + ".xcframework")
    info_path = os.path.join(xcframework, "Info.plist")
    if not os.path.isfile(info_path):
        print("SConstruct: {} is missing; run tools/fetch_meta_sdk.sh.".format(xcframework))
        Exit(1)
    with open(info_path, "rb") as f:
        info = plistlib.load(f)
    want_variant = "simulator" if env["ios_simulator"] else None
    for library in info["AvailableLibraries"]:
        if (
            library.get("SupportedPlatform") == "ios"
            and library.get("SupportedPlatformVariant") == want_variant
            and env["arch"] in library.get("SupportedArchitectures", [])
        ):
            return os.path.join(xcframework, library["LibraryIdentifier"])
    print("SConstruct: {} has no ios {} slice for {}.".format(xcframework, variant, env["arch"]))
    Exit(1)


framework_flags = ["-F" + meta_slice(framework) for framework in META_FRAMEWORKS]

env = env.Clone()
env.Append(CPPPATH=["src/ios"])
env.Append(CCFLAGS=framework_flags)
env.Append(
    LINKFLAGS=framework_flags
    + [
        "-framework", "FBSDKCoreKit",
        "-framework", "FBSDKCoreKit_Basics",
        "-framework", "FBAEMKit",
        "-framework", "AppTrackingTransparency",
        "-framework", "UIKit",
        "-framework", "Foundation",
        "-install_name", "@rpath/{0}.framework/{0}".format(name),
        "-Wl,-rpath,@loader_path/..",
    ]
)

objc_env = env.Clone()
objc_env.Append(CCFLAGS=["-fobjc-arc"])

objects = []
for source in Glob("src/ios/*.cpp"):
    stem = os.path.splitext(os.path.basename(str(source)))[0]
    objects += env.SharedObject(target="{}/obj/{}".format(out_dir, stem), source=source)
for source in Glob("src/ios/*.mm"):
    stem = os.path.splitext(os.path.basename(str(source)))[0]
    objects += objc_env.SharedObject(target="{}/obj/{}".format(out_dir, stem), source=source)

library = env.SharedLibrary(
    target="{}/{}".format(out_dir, name),
    source=objects,
    SHLIBPREFIX="",
    SHLIBSUFFIX="",
)
Default(library)
