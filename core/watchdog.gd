extends Node
## Watchdog — self-healing loop
## Stub for Phase 1

var command_bus: Node
var bridge_client: Node


func _ready() -> void:
	print("[Watchdog] Initialized (passive mode)")
