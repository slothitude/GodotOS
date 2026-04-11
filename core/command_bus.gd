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
		"event":
			result = _handle_event_command(command)
		"vfs":
			result = _handle_vfs_command(command)
		"app":
			result = _handle_app_command(command)
		"input":
			result = _handle_input_command(command)
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


func _handle_event_command(command: Dictionary) -> Dictionary:
	var router := Engine.get_singleton("EventRouter") if Engine.has_singleton("EventRouter") else null
	if not router:
		return {"error": "EventRouter not available"}
	match command.action:
		"emit":
			router.emit(command.params.get("channel", ""), command.params.get("data"))
			return {"ok": true}
		"subscribe":
			return {"error": "Use EventRouter.subscribe() directly — subscriptions are code-level"}
		"history":
			return {"events": router.get_history(command.params.get("limit", 20))}
		"channels":
			return {"channels": router.get_channels()}
		_:
			return {"error": "Unknown event action: %s" % command.action}


func _handle_vfs_command(command: Dictionary) -> Dictionary:
	var vfs := Engine.get_singleton("VirtualFS") if Engine.has_singleton("VirtualFS") else null
	if not vfs:
		return {"error": "VirtualFS not available"}
	match command.action:
		"resolve":
			return {"host_path": vfs.resolve(command.params.get("path", ""))}
		"virtualize":
			return {"virtual_path": vfs.virtualize(command.params.get("path", ""))}
		"mounts":
			return {"mounts": vfs.get_mounts()}
		"home":
			return {"home": vfs.get_home()}
		_:
			return {"error": "Unknown VFS action: %s" % command.action}


func _handle_app_command(command: Dictionary) -> Dictionary:
	var launcher := Engine.get_singleton("AppLauncher") if Engine.has_singleton("AppLauncher") else null
	if not launcher:
		return {"error": "AppLauncher not available"}
	match command.action:
		"launch":
			var win_id = launcher.launch(command.params.get("app_id", ""), command.params)
			if win_id == "":
				return {"error": "Failed to launch app"}
			return {"ok": true, "window_id": win_id}
		"close":
			launcher.close(command.params.get("app_id", ""))
			return {"ok": true}
		"list":
			return {"apps": launcher.list_apps()}
		_:
			return {"error": "Unknown app action: %s" % command.action}


func _handle_input_command(command: Dictionary) -> Dictionary:
	var router := Engine.get_singleton("InputRouter") if Engine.has_singleton("InputRouter") else null
	if not router:
		return {"error": "InputRouter not available"}
	match command.action:
		"focused":
			return {"window_id": router.get_focused_window_id()}
		_:
			return {"error": "Unknown input action: %s" % command.action}


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
