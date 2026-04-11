class_name GCVFSTool
extends RefCounted
## VFS navigation tool for the AI agent
## Lets the agent resolve virtual paths, list mounts, and navigate the virtual filesystem.

var tool_name := "VFS"
var description := "Navigate the virtual filesystem in GodotOS — resolve paths, list mounts"
var is_read_only := true


func get_input_schema() -> Dictionary:
	return {
		"type": "object",
		"properties": {
			"action": {
				"type": "string",
				"enum": ["resolve", "virtualize", "mounts", "home"],
				"description": "VFS action to perform"
			},
			"path": {
				"type": "string",
				"description": "Path to resolve or virtualize"
			}
		},
		"required": ["action"]
	}


func execute(input: Dictionary, context: Dictionary) -> Dictionary:
	var action: String = input.get("action", "")

	var vfs = Engine.get_singleton("VirtualFS") if Engine.has_singleton("VirtualFS") else null
	if not vfs:
		return {"success": false, "error": "VirtualFS not available"}

	match action:
		"resolve":
			var path: String = input.get("path", "")
			if path == "":
				return {"success": false, "error": "path required"}
			var resolved = vfs.resolve(path)
			return {"success": true, "data": {"virtual": path, "host": resolved}}
		"virtualize":
			var path: String = input.get("path", "")
			if path == "":
				return {"success": false, "error": "path required"}
			var virtual = vfs.virtualize(path)
			return {"success": true, "data": {"host": path, "virtual": virtual}}
		"mounts":
			var mounts = vfs.get_mounts()
			var result := []
			for vp in mounts:
				result.append({"virtual": vp, "host": mounts[vp]})
			return {"success": true, "data": {"mounts": result}}
		"home":
			return {"success": true, "data": {"home": vfs.get_home()}}
		_:
			return {"success": false, "error": "Unknown action: %s" % action}


func to_tool_definition() -> Dictionary:
	return {
		"name": tool_name,
		"description": description,
		"input_schema": get_input_schema(),
	}
