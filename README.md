# godot-meta-events-ios

A Godot 4.7 addon that wraps Meta's iOS SDK (FBSDKCoreKit 19.0.0) so a game can
log Meta App Events. It exists to measure iOS installs of Meta (Facebook and
Instagram) ad campaigns through SKAdNetwork and AEM, which needs the SDK inside
the app.

- Games use the release zip, `dist/godot-meta-events-ios-<version>.zip`, not this source.
- One GDScript call: `MetaSDK.log_event(name, params)`.
- iOS only. On every other platform the call does nothing.
- iOS 15.0 or later: Meta's frameworks need it. That is Godot 4.7's default
  `application/min_ios_version`; do not lower it in the iOS export preset.
- The native library is a GDExtension built against godot-cpp 4.5
  (`compatibility_minimum = "4.5"`), so Godot 4.7.x updates need no rebuild.

## Install

1. Unzip the release at the game's project root so that `addons/meta_sdk/` appears.
   Extract with a tool that restores symlinks, such as `unzip` or
   `ditto -xk godot-meta-events-ios-<version>.zip .` on macOS. Meta's xcframeworks hold symlinks
   (their Mac Catalyst slices are versioned bundles) and are signed by Meta. A
   symlink-flattening install, such as repacking with plain `zip -r` or some
   asset-store installs, breaks those signatures and Xcode then refuses to build
   with "The signature of FBSDKCoreKit.xcframework cannot be verified". Check an
   install with:

   ```sh
   codesign --verify --strict addons/meta_sdk/bin/ios/FBSDKCoreKit.xcframework
   ```

   Commit the files with git, which stores symlinks. If the game keeps large
   binaries in Git LFS, put the whole `bin/ios` folder in LFS with this single
   `.gitattributes` rule:

   ```gitattributes
   addons/meta_sdk/bin/ios/** filter=lfs diff=lfs merge=lfs -text
   ```

   Rules for the binaries alone (`meta_sdk.ios.template_*`, `FBSDKCoreKit`,
   `FBSDKCoreKit_Basics`, `FBAEMKit`) are not enough: Meta's xcframeworks also hold
   Swift `*.abi.json` files and dSYM `Relocations/*.yml` files, about 40 MB of text
   that would then go into plain Git history with every addon version. LFS
   leaves the symlinks as Git symlinks, so the signatures still verify after a clone.
2. Project > Project Settings > Plugins: enable **Meta SDK**.
3. Fill in the three settings (Project Settings > General, section **Meta Sdk**,
   or edit `project.godot` directly). The plugin registers them as basic settings,
   so they show without the **Advanced Settings** toggle once it is enabled:

   ```ini
   [meta_sdk]

   app_id="1234567890"
   client_token="..."
   display_name="My Game"
   ```

   - `meta_sdk/app_id`: the numeric Facebook App ID, digits only.
   - `meta_sdk/client_token`: Meta App Dashboard > Settings > Advanced > Client token.
   - `meta_sdk/display_name`: optional; falls back to `application/config/name`.
4. In the iOS export preset, leave the **Meta Sdk > Add Skadnetwork Ids**
   option (`meta_sdk/add_skadnetwork_ids`, default on) on so the export writes
   Meta's two SKAdNetwork IDs (`v9wttpbfk9.skadnetwork`, `n38lu8286q.skadnetwork`).
   **Turn it off when the AdMob plugin is enabled**: AdMob already writes Meta's
   IDs, and a second `SKAdNetworkItems` key would be a duplicate. The editor warns
   when both are on.
5. Export iOS as an Xcode project: turn on `application/export_project_only`
   ("Export Project Only") in the iOS preset, then build in Xcode. Godot copies the
   addon's Meta frameworks into the project but flattens their symlinks, which
   breaks Meta's signatures; the addon's export plugin puts exact copies back once
   the Xcode project is written. That step is verified for project-only exports.
   A one-click export, where Godot runs xcodebuild itself, is untested; the repair
   runs only after Godot has written the project, so do not rely on it there.

What the export does, and what it does when something is missing:

- With a valid App ID and token it adds `FacebookAppID`, `FacebookClientToken`,
  `FacebookDisplayName` and (when the option is on) `SKAdNetworkItems` to the
  Info.plist. The display name is XML-escaped.
- With a missing or invalid App ID or token the export prints
  `Meta SDK iOS configuration error: ...`, writes no Meta keys and still finishes.
  The app then starts without Meta: it prints `MetaSDK: FacebookAppID is missing
  from Info.plist; Meta SDK not started.` and runs normally; `log_event` does
  nothing. It never crashes.
- Debug builds print `MetaSDK: started` and `MetaSDK: logged <name>` for each
  event; release builds print nothing for normal operation.
- `addons/meta_sdk/bin/ios/` holds a `.gdignore`, so Godot neither imports that
  folder nor packs it into game data on any platform. Without it, every export
  with "Export all resources" would pack the 26 Swift `*.abi.json` files inside
  Meta's xcframeworks (about 54 MB). iOS exports still embed the xcframeworks,
  because `meta_sdk.gdextension` names them by path. Keep the file when you copy
  or commit the addon; the editor warns at startup when it is missing.
- An Xcode project export also gets a `.gdignore` in
  `<Name>/dylibs/addons/meta_sdk/bin/ios/`, next to the restored Meta copies. When
  the export folder is inside the project (such as `build/ios/`), this keeps the
  next export from packing those copies' `*.abi.json` files.
- A PCK/ZIP export of the iOS preset (`--export-pack`) writes no Xcode project,
  so the framework repair is skipped and prints nothing.

## Upgrade

Delete the old addon before unzipping the new release, then check the install:

```sh
rm -rf addons/meta_sdk
unzip -q godot-meta-events-ios-<version>.zip -d .
codesign --verify --strict addons/meta_sdk/bin/ios/FBSDKCoreKit.xcframework
```

Unzipping over an old copy keeps every file the new release no longer has. A
leftover file inside one of Meta's xcframeworks breaks its signature, and Xcode
then refuses to build.

## API

```gdscript
MetaSDK.log_event("fb_mobile_tutorial_completion", {"fb_success": 1})
MetaSDK.log_event("level_cleared", {"level": 3, "time": 41.5, "perfect": true, "mode": "endless"})
```

`MetaSDK.log_event(name: String, params: Dictionary = {})`

- Parameter keys must be `String` or `StringName`. Values must be `String`,
  `StringName`, `int`, a finite `float` or `bool`. A pair with any other key or
  value (`null`, `Array`, `Dictionary`, `Vector2`, `NAN`, `INF`, ...) is dropped
  with a warning and the event is still sent with the remaining pairs. The check
  runs on every platform, so a desktop run prints the same warnings as iOS.
- An empty name is ignored with a warning.
- Event name length, the number of parameters and the like are checked by Meta's
  SDK, not here.
- It is a no-op wherever the native `MetaSDKIOS` singleton is missing: desktop,
  the editor and Android. Calling it is always safe, so game code needs no
  platform checks.
- Prefer Meta's standard event names, such as `fb_mobile_tutorial_completion`
  with `fb_success`, so ads can optimise for them. See Meta's App Events
  reference for the list and each event's parameters.

The SDK starts at app launch and logs installs and app activation on its own
(`fb_mobile_activate_app`); it batches events and sends them in the background.

## App Store privacy

Meta's frameworks bring their own privacy manifests (`PrivacyInfo.xcprivacy`),
which Xcode merges into the app's privacy report. FBSDKCoreKit 19.0.0 declares
`NSPrivacyTracking = true` with the tracking domain `ep1.facebook.com`, and lists
the Device ID as collected, linked to the user and used for tracking (third-party
advertising, analytics, app functionality). Every game that adds this addon must
revisit its App Privacy answers in App Store Connect and its privacy policy to
match. Apple blocks requests to a declared tracking domain until the player allows
tracking through App Tracking Transparency, which this addon never asks for (see
below).

Since 12 October 2026, Meta's SDK 19.0.0 also attaches the screen title and the
AppLink URL to every logged event. Meta's switches for this are
`FBSDKAutoLogMetaDataEnabled = false` in the Info.plist or "Automatically include
more app event details" in Events Manager; the addon writes no such key, so the
Events Manager setting decides.

## What it does not do

- **Android.** Android builds load empty stub libraries and get no `MetaSDK`
  behaviour. Android installs have to be measured without the SDK; an Android
  plugin (an AAR) could be added later behind the same GDScript API.
- **ATT.** There is no App Tracking Transparency prompt and no
  `NSUserTrackingUsageDescription`. Meta measures through SKAdNetwork and AEM.
- **Advertiser Tracking Enabled.** It never sets `Settings.isAdvertiserTrackingEnabled`
  (Meta's old iOS 14 advice). On iOS 17 and later Meta's SDK ignores that setter and
  reads the ATT status itself, and setting it to true on iOS 15 or 16 without the
  player's ATT consent would break Apple's rules. Without ATT, events go to Meta
  without tracking consent; it only changes once the game adds an ATT prompt.
- **Deep links.** It writes no `fb{AppID}` URL scheme (`CFBundleURLTypes`), no
  `LSApplicationQueriesSchemes` and forwards no `openURL`, so re-engagement ad deep
  links do not work.
- **Purchases.** There is no `log_purchase`.
- **Consent.** The SDK starts at launch for every player; the game is responsible
  for any consent requirement (for example GDPR).

## Build prerequisites

Only the maintainer of the addon needs these; games use the release zip.

- A Mac with Xcode (iOS SDK) and the command line tools.
- `godot` (4.7.x) on the PATH.
- `git submodule update --init` for `godot-cpp` (pinned to `godot-4.5-stable`).
- Homebrew `zig` (`brew install zig`) for the Windows and Linux stubs.
- Android NDK `28.2.13676358` at `~/Library/Android/sdk/ndk/28.2.13676358`
  (set `ANDROID_NDK` for another location) for the Android stubs.
- A signing identity. `tools/build_ios.sh` signs the iOS libraries with the first
  valid `Apple Development: Ozan YILDIZ (8F768A29F9)` identity from
  `security find-identity -v -p codesigning`; set `CODESIGN_IDENTITY` (a SHA-1 or
  name) to use another. Each signature carries a secure timestamp, so it stays
  valid after that certificate expires.
- Network access: the first build downloads Meta's frameworks, and every build
  asks Apple's timestamp server for the signature timestamps (the build fails when
  it cannot reach it). SCons 4.9.1 is installed into a repo-local `.venv`
  automatically.

Tools:

| Command | What it does |
|---|---|
| `tools/build_stubs.sh` | Builds the no-op libraries for macOS, Windows, Linux and Android and checks each exports `meta_sdk_library_init`. |
| `tools/build_ios.sh` | Fetches Meta SDK 19.0.0 (`tools/fetch_meta_sdk.sh`, SHA-256 checked), builds and signs (with a secure timestamp) `meta_sdk.ios.template_{debug,release}.xcframework` with the `plugin.cfg` version as `CFBundleShortVersionString`, copies Meta's three xcframeworks into `addons/meta_sdk/bin/ios/` and writes that folder's `.gdignore`. A cold build takes several minutes. |
| `tools/run_tests.sh` | Runs the headless GDScript tests in `tests/`. |
| `tools/run_simulator_demo.sh` | Exports `demo/`, builds it for the iOS Simulator, runs it for 20 s, keeps the logs in `build/ios/` and fails unless the console shows `MetaSDK: started` and `MetaSDK: logged meta_sdk_demo`. |

The Simulator demo needs workarounds that apply only to that script, not to games:
Godot 4.7.2's official iOS template ships an x86_64-only Simulator `libgodot.a`
while the current Simulator runs arm64 only, so the script adds an arm64 slice
retagged from the device slice (`tools/retag_ios_simulator.py`) plus two Metal
constants the Simulator lacks, and the demo uses the Compatibility renderer. Games
build for real devices and need none of this. The demo uses a dummy App ID, so it
never sends events for a real app.

## Release

1. Set `version` in `addons/meta_sdk/plugin.cfg` to the bundled Meta SDK version,
   such as `19.0.0` (and update its description if that version changed): the
   addon's version follows Meta's. It must be one to three dot-separated integers:
   `tools/build_ios.sh` writes it into the iOS frameworks'
   `CFBundleShortVersionString`.
2. Run `tools/release.sh`. It reads the version, runs `tools/build_stubs.sh` and
   `tools/build_ios.sh`, imports the project, runs `tools/run_tests.sh`, copies
   `addons/meta_sdk` (without `.DS_Store`) and zips it with `zip -y`, which keeps
   the xcframework symlinks.
3. The script then fails unless the zip lists every file a game needs (the plugin
   files, the `export/` scripts, their `.uid` files, the `Info.plist` of all five
   xcframeworks, `bin/ios/.gdignore` and all six stub libraries), nothing from
   `.godot/`, `vendor/` or `build/`, the same number of symlinks as the source,
   and unzipped xcframeworks that pass `codesign --verify --strict`.
4. The result is `dist/godot-meta-events-ios-<version>.zip`. `dist/` is not committed.
   Meta's three xcframeworks must stay unmodified, so the zip is large (about 135
   MB of Meta frameworks, mostly Mac Catalyst slices and debug symbols).

The zip's root is `addons/meta_sdk/`:

```
addons/meta_sdk/
  plugin.cfg  plugin.gd  meta_sdk.gd  meta_sdk.gdextension  export/
  bin/ios/.gdignore                         # keeps bin/ios out of exported game data
  bin/ios/meta_sdk.ios.template_debug.xcframework
  bin/ios/meta_sdk.ios.template_release.xcframework
  bin/ios/FBSDKCoreKit.xcframework          # Meta's own, signed, unmodified
  bin/ios/FBSDKCoreKit_Basics.xcframework
  bin/ios/FBAEMKit.xcframework
  bin/macos/libmeta_sdk_stub.macos.dylib    # arm64 + x86_64
  bin/windows/meta_sdk_stub.windows.x86_64.dll
  bin/linux/libmeta_sdk_stub.linux.x86_64.so
  bin/android/libmeta_sdk_stub.android.{arm64,arm32,x86_64}.so
```

## Updating Meta SDK

1. In `tools/fetch_meta_sdk.sh`, change `VERSION` and the three SHA-256 values in
   `FRAMEWORKS`. Download each `<Name>-Dynamic_XCFramework.zip` from the
   `facebook-ios-sdk` release (`FBSDKCoreKit`, `FBSDKCoreKit_Basics`, `FBAEMKit`) and
   take its checksum with `shasum -a 256`. Use the dynamic zips only; the
   xcframeworks stay unmodified and unsliced. GitHub also lists each asset's
   SHA-256 (`gh api repos/facebook/facebook-ios-sdk/releases/tags/v<version> -q
   '.assets[] | .name + " " + .digest'`); the two must match.
2. A new major version can change the API that `src/ios/meta_sdk_ios.mm` calls;
   read Meta's release notes and fix the build. Also check that Meta's
   `MinimumOSVersion` (in each framework's `Info.plist`) is not above `MIN_IOS` in
   `tools/build_ios.sh`; 19.0.0 needs iOS 15.0.
3. Delete `build/ios` (`rm -rf build/ios`). It holds the SCons objects, and SCons
   does not track Meta's headers or binaries, so without this the build would keep
   objects compiled against the old SDK.
4. Run `tools/build_ios.sh`, then `tools/run_simulator_demo.sh`, which checks that
   `build/ios/console.log` contains `MetaSDK: started` and
   `MetaSDK: logged meta_sdk_demo`.
5. Set `version` to the new Meta SDK version (and the SDK version in the
   `plugin.cfg` description and this README) and run `tools/release.sh`.
