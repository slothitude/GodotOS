class_name GCAppTool
extends GCBaseTool
## App management tool for the AI agent


func _init() -> void:
	super("App", "List, launch, and close applications in GodotOS", {})
	is_read_only = false


func get_input_schema() -> Dictionary:
	return {
		"type": "object",
		"properties": {
			"action": {
				"type": "string",
				"enum": ["list", "launch", "close", "info"],
				"description": "The app action to perform"
			},
			"app_id": {
				"type": "string",
				"description": "Application ID (e.g. 'terminal', 'editor')"
			},
			"title": {
				"type": "string",
				"description": "Window title override for launch"
			}
		},
		"required": ["action"]
	}


func execute(input: Dictionary, context: Dictionary) -> Dictionary:
	var action: String = input.get("action", "")

	var launcher = Engine.get_singleton("AppLauncher") if Engine.has_singleton("AppLauncher") else null
	if not launcher:
		return {"success": false, "error": "AppLauncher not available"}

	match action:
		"list":
			var apps = launcher.list_apps()
			return {"success": true, "data": {"apps": apps}}
		"launch":
			var app_id: String = input.get("app_id", "")
			if app_id == "":
				return {"success": false, "error": "app_id required"}
			var extra := {}
			if input.has("title"):
				extra["title"] = input["title"]
			var win_id = launcher.launch(app_id, extra)
			if win_id == "":
				return {"success": false, "error": "Failed to launch app: %s" % app_id}
			return {"success": true, "data": {"app_id": app_id, "window_id": win_id}}
		"close":
			var app_id: String = input.get("app_id", "")
			if app_id == "":
				return {"success": false, "error": "app_id required"}
			launcher.close(app_id)
			return {"success": true, "data": {"closed": app_id}}
		"info":
			var app_id: String = input.get("app_id", "")
			if app_id == "":
				return {"success": false, "error": "app_id required"}
			var manifest = launcher.get_app(app_id)
			if manifest.is_empty():
				return {"success": false, "error": "App not found: %s" % app_id}
			manifest["running"] = launcher.is_running(app_id)
			return {"success": true, "data": manifest}
		_:
			return {"success": false, "error": "Unknown action: %s" % action}


func to_tool_definition() -> Dictionary:
	return {
		"name": tool_name,
		"description": description,
		"input_schema": get_input_schema(),
	}
