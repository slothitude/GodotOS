extends Node
## CommandBus — ALL actions in GodotOS flow through here.
## No UI, no AI agent, no app touches Linux directly.
## Everything is a validated, logged, reversible command.

var bridge: Node       # BridgeClient
var registry: RefCounted  # GCToolRegistry
var state: Node        # StateEngine
var permissions: RefCounted  # GCPermissionManager

var _log: Array[Dictionary] = []
var _pending: Dictionary = {}       # id → command
var _sequence: int = 0

signal command_started(id: String, command: Dictionary)
signal command_completed(id: String, result: Dictionary)
signal command_failed(id: String, error: String)
signal command_rejected(id: String, reason: String)

## Execute a command. Returns a Promise-like signal via id.
## All commands follow this schema:
## {
##   "target": "filesystem" | "process" | "window" | "ai" | "system",
##   "action": "read_file" | "create_process" | "open_window" | ...,
##   "params": { ... },
##   "source": "user" | "agent" | "system" | "watchdog",
##   "reversible": true/false
## }
func execute(command: Dictionary) -> String:
	_sequence += 1
	var id := "cmd_%05d" % _sequence
	command["id"] = id
	command["timestamp"] = Time.get_unix_time_from_system()

	# Validate structure
	var err := _validate(command)
	if err != "":
		command_rejected.emit(id, err)
		return id

	# Permission check
	if not permissions.check(command):
		command_rejected.emit(id, "Permission denied: %s.%s" % [command.target, command.action])
		return id

	# Log it
	_log.append(command.duplicate())
	state.record_command(command)

	# Dispatch
	command_started.emit(id, command)
	_pending[id] = command
	_dispatch.call_deferred(id, command)
	return id

func _dispatch(id: String, command: Dictionary) -> void:
	var result: Dictionary

	match command.get("target", ""):
		"filesystem":
			result = await bridge.call_service("fs", command.action, command.params)
		"process":
			result = await bridge.call_service("process", command.action, command.params)
		"system":
			result = await bridge.call_service("system", command.action, command.params)
		"network":
			result = await bridge.call_service("network", command.action, command.params)
		"window":
			result = _handle_window_command(command)
		"ai":
			result = await _handle_ai_command(command)
		_:
			# Try service registry for registered tools
			var tool = registry.get_tool(command.target)
			if tool:
				result = await tool.execute(command.params, _build_context())
			else:
				result = {"error": "Unknown target: %s" % command.target}

	_pending.erase(id)

	if result.has("error"):
		state.record_failure(id, result.error)
		command_failed.emit(id, result.error)
	else:
		state.record_result(id, result)
		command_completed.emit(id, result)

func _validate(cmd: Dictionary) -> String:
	if not cmd.has("target"):
		return "Missing 'target'"
	if not cmd.has("action"):
		return "Missing 'action'"
	if not cmd.has("params"):
		cmd["params"] = {}
	return ""

func _handle_window_command(command: Dictionary) -> Dictionary:
	var wm := Engine.get_singleton("WindowManager") if Engine.has_singleton("WindowManager") else null
	if not wm:
		return {"error": "WindowManager not available"}
	match command.action:
		"open":
			wm.open_app(command.params.get("scene", ""), command.params)
			return {"ok": true}
		"close":
			wm.close_window(command.params.get("window_id", ""))
			return {"ok": true}
		"focus":
			wm.focus_window(command.params.get("window_id", ""))
			return {"ok": true}
		_:
			return {"error": "Unknown window action: %s" % command.action}

func _handle_ai_command(command: Dictionary) -> Dictionary:
	# Routes to the AI console's query engine
	var console := Engine.get_singleton("AIConsole") if Engine.has_singleton("AIConsole") else null
	if not console:
		return {"error": "AI console not running"}
	return await console.run_query(command.params.get("prompt", ""), command.params)

func _build_context() -> Dictionary:
	return {
		"command_bus": self,
		"bridge_client": bridge,
		"state_engine": state,
	}

## Get the full command log (for debugging, snapshots)
func get_log() -> Array[Dictionary]:
	return _log.duplicate()

## Get all pending (in-flight) commands
func get_pending() -> Dictionary:
	return _pending.duplicate()
