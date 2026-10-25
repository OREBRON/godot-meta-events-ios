extends RefCounted
## Builds the Info.plist fragment the Meta iOS SDK reads at launch.
##
## Kept free of editor classes so tests can load it. The export plugin adds the
## fragment with add_apple_embedded_platform_plist_content.

const APP_ID_SETTING := "meta_sdk/app_id"
const CLIENT_TOKEN_SETTING := "meta_sdk/client_token"
const DISPLAY_NAME_SETTING := "meta_sdk/display_name"
const SKADNETWORK_OPTION := "meta_sdk/add_skadnetwork_ids"
const SKADNETWORK_IDS := ["v9wttpbfk9.skadnetwork", "n38lu8286q.skadnetwork"]
const ADMOB_PLUGIN := "res://addons/admob/plugin.cfg"
const ADMOB_SKADNETWORK_WARNING := "AdMob already adds Meta's SKAdNetwork IDs; turn this off to avoid a duplicate SKAdNetworkItems key."


## Returns {"error": OK, "content": fragment} or {"error": ERR_INVALID_DATA, "message": reason}.
## The App ID must be digits only; the token must be non-empty without whitespace.
static func plist(app_id: String, client_token: String, display_name: String, add_skadnetwork: bool) -> Dictionary:
	if app_id.is_empty() or not app_id.lstrip("0123456789").is_empty():
		return _error("Set %s to the numeric Facebook App ID." % APP_ID_SETTING)
	if client_token.is_empty():
		return _error("Set %s to the Client Token from Meta App Dashboard > Settings > Advanced." % CLIENT_TOKEN_SETTING)
	for whitespace in [" ", "\t", "\n", "\r"]:
		if client_token.contains(whitespace):
			return _error("%s must not contain spaces or line breaks." % CLIENT_TOKEN_SETTING)
	var content := "<key>FacebookAppID</key><string>%s</string>\n" % app_id
	content += "<key>FacebookClientToken</key><string>%s</string>\n" % client_token.xml_escape(true)
	content += "<key>FacebookDisplayName</key><string>%s</string>\n" % display_name.xml_escape(true)
	if add_skadnetwork:
		content += "<key>SKAdNetworkItems</key><array>\n"
		for id: String in SKADNETWORK_IDS:
			content += "\t<dict><key>SKAdNetworkIdentifier</key><string>%s</string></dict>\n" % id
		content += "</array>\n"
	return {"error": OK, "content": content}


## Returns a warning when the option would add SKAdNetworkItems a second time
## because AdMob already writes Meta's IDs, otherwise "".
static func skadnetwork_warning(add_skadnetwork: bool, enabled_plugins: PackedStringArray) -> String:
	if add_skadnetwork and enabled_plugins.has(ADMOB_PLUGIN):
		return ADMOB_SKADNETWORK_WARNING
	return ""


static func _error(message: String) -> Dictionary:
	return {"error": ERR_INVALID_DATA, "message": message}
