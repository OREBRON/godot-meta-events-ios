extends Node
## Simulator demo: logs one Meta app event with every supported value type.
## tools/run_simulator_demo.sh checks the console for "MetaSDK: logged meta_sdk_demo".


func _ready() -> void:
	MetaSDK.log_event("meta_sdk_demo", {"source": "simulator", "attempt": 1, "ratio": 0.5, "ok": true})
