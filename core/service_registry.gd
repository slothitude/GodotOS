class_name GCToolRegistry
extends RefCounted
## Tool registration and lookup system
## Direct copy from GodotCode — tools get registered in Phase 3

var _tools: Dictionary = {}  # tool_name -> GCBaseTool instance


func register(tool) -> void:  # GCBaseTool
	_tools[tool.tool_name] = tool


func unregister(tool_name: String) -> void:
	_tools.erase(tool_name)


func get_tool(tool_name: String):
	return _tools.get(tool_name)


func has_tool(tool_name: String) -> bool:
	return _tools.has(tool_name)


func get_all_tools() -> Dictionary:
	return _tools


func get_tool_names() -> Array:
	return _tools.keys()


## Export all tools in tool definition format for API requests
func to_api_format() -> Array:
	var result: Array = []
	for tool_name in _tools:
		var tool = _tools[tool_name]
		result.append(tool.to_tool_definition())
	return result
