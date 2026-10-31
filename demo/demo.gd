extends Node
## Simulator demo: logs one Meta app event with every supported value type, then
## asks for tracking permission. tools/run_simulator_demo.sh checks the console
## for "MetaSDK: logged meta_sdk_demo"; the tracking prompt waits for a tap.


func _ready() -> void:
	MetaSDK.log_event("meta_sdk_demo", {"source": "simulator", "attempt": 1, "ratio": 0.5, "ok": true})
	MetaSDK.request_tracking_authorization(func(status: int) -> void:
		print("MetaSDK demo: tracking status ", status))
