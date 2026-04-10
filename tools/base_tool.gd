class_name GCBaseTool
extends RefCounted
## Abstract base class for all GodotCode tools

var tool_name: String
var description: String
var input_schema: Dictionary
var is_read_only: bool = true


func _init(p_name: String = "", p_desc: String = "", p_schema: Dictionary = {}) -> void:
	tool_name = p_name
	description = p_desc
	input_schema = p_schema


func validate_input(input: Dictionary) -> Dictionary:
	# Return {"valid": true} or {"valid": false, "error": "..."}
	return {"valid": true}


func check_permissions(input: Dictionary, context: Dictionary) -> Dictionary:
	# Return {"behavior": "allow"} or {"behavior": "ask", "message": "..."} or {"behavior": "deny"}
	if is_read_only:
		return {"behavior": "allow"}
	return {"behavior": "ask", "message": "Tool '%s' requires permission" % tool_name}


func execute(input: Dictionary, context: Dictionary) -> Dictionary:
	# Return {"success": true, "data": {...}} or {"success": false, "error": "..."}
	push_error("execute() must be overridden in subclass: " + tool_name)
	return {"success": false, "error": "Not implemented"}


func to_tool_definition() -> Dictionary:
	return {
		"name": tool_name,
		"description": description,
		"input_schema": {
			"type": "object",
			"properties": input_schema
		}
	}


func has_vision_result(result: Dictionary) -> bool:
	return result.get("is_vision", false)


func to_api_result(result: Dictionary, tool_use_id: String) -> Dictionary:
	var content: String
	if result.get("success", false):
		content = str(result.get("data", ""))
	else:
		content = "Error: " + str(result.get("error", "Unknown error"))

	return {
		"type": "tool_result",
		"tool_use_id": tool_use_id,
		"content": content,
		"is_error": not result.get("success", false)
	}
