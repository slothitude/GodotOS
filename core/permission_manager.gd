class_name GCPermissionManager
extends RefCounted
## Permission prompt system with modes and rules
## Adapted from GodotCode for GodotOS — adds check() for CommandBus integration

var _settings  # GCSettings or null

# Rules: tool_name -> "allow" | "ask" | "deny"
var _rules: Dictionary = {
	"Read": "allow",
	"Glob": "allow",
	"Grep": "allow",
	"Write": "ask",
	"Edit": "ask",
	"Bash": "ask",
	"WebSearch": "allow",
	"WebFetch": "allow",
	"Agent": "allow",
	"TaskManage": "allow",
	"Schedule": "allow",
	"Sleep": "allow",
	"EnterPlanMode": "allow",
	"ErrorMonitor": "allow",
	"Window": "allow",
}


func get_current_mode() -> String:
	if _settings:
		return _settings.get_permission_mode()
	return "default"


## Check a command from CommandBus. Maps target.action to a tool name and delegates.
func check(command: Dictionary) -> bool:
	var tool_name := _map_command_to_tool(command)
	var decision := check_tool_permission(tool_name, command.get("params", {}), {})
	return decision.behavior != "deny"


func _map_command_to_tool(command: Dictionary) -> String:
	var target: String = command.get("target", "")
	var action: String = command.get("action", "")
	# Simple mapping: filesystem→Read/Write, process→Bash, window→Window, etc.
	match target:
		"filesystem":
			if action.begins_with("read") or action.begins_with("list") or action.begins_with("stat"):
				return "Read"
			return "Write"
		"process":
			return "Bash"
		"window":
			return "Window"
		"system", "network":
			return "Read"
		"ai":
			return "Agent"
		_:
			return target.capitalize()


func check_tool_permission(tool_name: String, tool_input: Dictionary, context: Dictionary) -> Dictionary:
	var mode := get_current_mode()

	# Bypass mode: allow everything
	if mode == "bypass":
		return {"behavior": "allow"}

	# Check rules
	var rule: String = _rules.get(tool_name, "ask")

	# Plan mode: only allow read-only tools
	if mode == "plan":
		var read_only_tools := ["Read", "Glob", "Grep", "WebSearch", "WebFetch", "ErrorMonitor"]
		if tool_name in read_only_tools:
			return {"behavior": "allow"}
		return {"behavior": "deny", "message": "Plan mode: only read-only tools allowed"}

	match rule:
		"allow":
			return {"behavior": "allow"}
		"deny":
			return {"behavior": "deny", "message": "Tool '%s' is blocked by permission rules" % tool_name}
		_:
			return {"behavior": "ask", "message": "Tool '%s' requires your approval" % tool_name}


func set_rule(tool_name: String, behavior: String) -> void:
	_rules[tool_name] = behavior


func get_rules() -> Dictionary:
	return _rules.duplicate()
