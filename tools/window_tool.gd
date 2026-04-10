class_name GCWindowTool
extends RefCounted
## Window management tool for the AI agent

var tool_name := "Window"
var description := "Open, close, and focus application windows in GodotOS"
var is_read_only := false


func get_input_schema() -> Dictionary:
	return {
		"type": "object",
		"properties": {
			"action": {
				"type": "string",
				"enum": ["open", "close", "focus", "list"],
				"description": "The window action to perform"
			},
			"scene": {
				"type": "string",
				"description": "Scene path for open action"
			},
			"window_id": {
				"type": "string",
				"description": "Window ID for close/focus actions"
			},
			"title": {
				"type": "string",
				"description": "Window title for open action"
			}
		},
		"required": ["action"]
	}


func execute(input: Dictionary, context: Dictionary) -> Dictionary:
	var action: String = input.get("action", "")

	var wm_node = null
	if Engine.has_singleton("WindowManager"):
		wm_node = Engine.get_singleton("WindowManager")

	if not wm_node:
		return {"success": false, "error": "WindowManager not available"}

	match action:
		"open":
			var scene := input.get("scene", "")
			var params := {
				"title": input.get("title", "Untitled"),
			}
			var id := wm_node.open_app(scene, params)
			return {"success": true, "data": {"window_id": id}}
		"close":
			var wid := input.get("window_id", "")
			wm_node.close_window(wid)
			return {"success": true, "data": {"closed": wid}}
		"focus":
			var wid := input.get("window_id", "")
			wm_node.focus_window(wid)
			return {"success": true, "data": {"focused": wid}}
		"list":
			var windows := wm_node.get_all_windows()
			var result := []
			for id in windows:
				var w: Dictionary = windows[id]
				result.append({"id": id, "scene": w.get("scene_path", ""), "title": w.get("params", {}).get("title", "")})
			return {"success": true, "data": {"windows": result}}
		_:
			return {"success": false, "error": "Unknown action: %s" % action}


func to_tool_definition() -> Dictionary:
	return {
		"name": tool_name,
		"description": description,
		"input_schema": get_input_schema(),
	}
