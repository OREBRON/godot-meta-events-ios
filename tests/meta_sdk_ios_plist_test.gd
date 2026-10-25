extends SceneTree

const Plist = preload("res://addons/meta_sdk/export/meta_sdk_ios_plist.gd")
const TOKEN := "0123456789abcdef0123456789abcdef"

var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ", message)

## Returns the FacebookDisplayName value as a plist reader would see it, or a
## marker string when the fragment cannot be read.
func display_name_in(fragment: String) -> String:
	var parser := XMLParser.new()
	if parser.open_buffer(("<plist><dict>" + fragment + "</dict></plist>").to_utf8_buffer()) != OK:
		return "<fragment did not open>"
	var element := ""
	var key := ""
	while parser.read() == OK:
		match parser.get_node_type():
			XMLParser.NODE_ELEMENT:
				element = parser.get_node_name()
			XMLParser.NODE_TEXT:
				var text := parser.get_node_data()
				if element == "key":
					key = text
				elif element == "string" and key == "FacebookDisplayName":
					return text.xml_unescape()
	return "<FacebookDisplayName not found>"

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var ok: Dictionary = Plist.plist("1609617600637476", TOKEN, "Tom & Jerry's <Run>", false)
	check(ok.error == OK, "Valid settings produce a fragment")
	check(ok.content.contains("<key>FacebookAppID</key><string>1609617600637476</string>"), "App ID key")
	check(ok.content.contains("<key>FacebookClientToken</key><string>%s</string>" % TOKEN), "Client token key")
	check(ok.content.contains("<key>FacebookDisplayName</key><string>Tom &amp; Jerry&apos;s &lt;Run&gt;</string>"), "Display name is XML-escaped")
	check(not ok.content.contains("SKAdNetworkItems"), "No SKAdNetwork IDs when the option is off")
	check(Plist.plist("1609617600637476", TOKEN, "Çiçek Koşusu", false).content.contains("<string>Çiçek Koşusu</string>"), "UTF-8 names stay intact")
	var sk: Dictionary = Plist.plist("1609617600637476", TOKEN, "Color Sprint", true)
	check(sk.content.count("<key>SKAdNetworkItems</key>") == 1 and sk.content.contains("v9wttpbfk9.skadnetwork") and sk.content.contains("n38lu8286q.skadnetwork"), "Both Meta SKAdNetwork IDs in one array")
	# XMLParser is non-validating (it accepts unescaped "&" and "<"), so well-formedness
	# is checked by reading the display name back out and comparing it to the input.
	for name in ["Tom & Jerry's <Run>", "Çiçek Koşusu"]:
		var fragment: String = Plist.plist("1609617600637476", TOKEN, name, false).content
		check(display_name_in(fragment) == name, "Display name round-trips through the plist XML: %s" % name)
	for bad in [["", TOKEN], ["16096x", TOKEN], ["-1", TOKEN], ["+1", TOKEN], ["1609617600637476", ""], ["1609617600637476", "abc def"], ["1609617600637476", "abc\n"]]:
		check(Plist.plist(bad[0], bad[1], "x", false).error == ERR_INVALID_DATA, "Rejects %s" % [bad])
	check(Plist.plist("", TOKEN, "x", false).message == "Set meta_sdk/app_id to the numeric Facebook App ID.", "App ID message")
	check(Plist.plist("1", "", "x", false).message == "Set meta_sdk/client_token to the Client Token from Meta App Dashboard > Settings > Advanced.", "Empty token message")
	check(Plist.plist("1", "a b", "x", false).message == "meta_sdk/client_token must not contain spaces or line breaks.", "Whitespace token message")
	check(Plist.skadnetwork_warning(true, PackedStringArray([Plist.ADMOB_PLUGIN])) == Plist.ADMOB_SKADNETWORK_WARNING, "Warns when AdMob also adds the IDs")
	check(Plist.skadnetwork_warning(false, PackedStringArray([Plist.ADMOB_PLUGIN])) == "", "No warning when the option is off")
	check(Plist.skadnetwork_warning(true, PackedStringArray(["res://addons/firebase/plugin.cfg"])) == "", "No warning without AdMob")
	if failures == 0:
		print("PASS")
	quit(failures)
