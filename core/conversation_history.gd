class_name GCConversationHistory
extends RefCounted
## Manages conversation message history with serialization

var _messages: Array = []  # Array of BaseMessage instances
var _settings: GCSettings
var _system_prompt: String = ""
var _is_dirty: bool = false


func get_messages() -> Array:
	return _messages


func get_display_messages() -> Array:
	var result: Array = []
	for msg in _messages:
		if msg is GCMessageTypes.UserMessage:
			result.append({"role": "user", "content": msg.content})
		elif msg is GCMessageTypes.AssistantMessage:
			var text: String = msg.text_content
			if text != "":
				result.append({"role": "assistant", "content": text})
			for tu in msg.tool_uses:
				result.append({"role": "tool", "content": "[Tool: %s]" % tu.name})
		elif msg is GCMessageTypes.ToolResultMessage:
			result.append({"role": "tool", "content": msg.content})
	return result


func add_user_message(text: String) -> GCMessageTypes.UserMessage:
	var msg := GCMessageTypes.UserMessage.new(text)
	_messages.append(msg)
	_is_dirty = true
	return msg


func add_assistant_message() -> GCMessageTypes.AssistantMessage:
	var msg := GCMessageTypes.AssistantMessage.new()
	_messages.append(msg)
	_is_dirty = true
	return msg


func add_tool_result(tool_use_id: String, content: Variant = "", is_error: bool = false) -> GCMessageTypes.ToolResultMessage:
	var msg := GCMessageTypes.ToolResultMessage.new(tool_use_id, content, is_error)
	_messages.append(msg)
	_is_dirty = true
	return msg


func set_system_prompt(prompt: String) -> void:
	_system_prompt = prompt


func get_system_prompt() -> String:
	return _system_prompt


func get_current_assistant() -> GCMessageTypes.AssistantMessage:
	for i in range(_messages.size() - 1, -1, -1):
		if _messages[i] is GCMessageTypes.AssistantMessage:
			return _messages[i]
	var msg := add_assistant_message()
	return msg


func clear() -> void:
	_messages.clear()
	_system_prompt = ""
	_is_dirty = false


func compact(keep_last_n: int = 4) -> void:
	if _messages.size() <= keep_last_n:
		return
	_messages = _messages.slice(_messages.size() - keep_last_n)
	_is_dirty = true


## Convert all messages to API format (for sending)
func to_api_messages() -> Array:
	var api_msgs: Array = []

	# Merge consecutive tool_results into single user messages
	var pending_tool_results: Array = []

	for msg in _messages:
		if msg is GCMessageTypes.ToolResultMessage:
			pending_tool_results.append(msg)
		else:
			# Flush pending tool results
			if pending_tool_results.size() > 0:
				api_msgs.append(_merge_tool_results(pending_tool_results))
				pending_tool_results.clear()

			if msg is GCMessageTypes.UserMessage:
				api_msgs.append(msg.to_api_dict())
			elif msg is GCMessageTypes.AssistantMessage:
				var d: Dictionary = msg.to_api_dict()
				# Only add if there's content
				if (d.get("content") as Array).size() > 0:
					api_msgs.append(d)

	# Flush remaining tool results
	if pending_tool_results.size() > 0:
		api_msgs.append(_merge_tool_results(pending_tool_results))

	return api_msgs


func _merge_tool_results(results: Array) -> Dictionary:
	var content_blocks: Array = []
	for r in results:
		# Handle both String and Array content (vision)
		if r.content is Array:
			# Vision content blocks pass through
			content_blocks.append({
				"type": "tool_result",
				"tool_use_id": r.tool_use_id,
				"content": r.content
			})
		else:
			var block := {
				"type": "tool_result",
				"tool_use_id": r.tool_use_id,
				"content": str(r.content)
			}
			if r.is_error:
				block["is_error"] = true
			content_blocks.append(block)

	# Mark if any result has is_error
	var has_error := false
	for r in results:
		if r.is_error:
			has_error = true
			break

	var result := {
		"role": "user",
		"content": content_blocks
	}
	return result


## Serialize to JSON-compatible array
func to_storage_array() -> Array:
	var result: Array = []
	for msg in _messages:
		result.append(msg.to_storage_dict())
	return result


## Load from JSON-compatible array
func from_storage_array(data: Array) -> void:
	_messages.clear()
	for d in data:
		var msg = GCMessageTypes.from_storage(d)
		if msg:
			_messages.append(msg)
	_is_dirty = false


## Save conversation to file
func save_to_file() -> bool:
	if not _is_dirty:
		return true

	var dir := _get_conversation_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)

	var path := dir.path_join("current_conversation.json")
	var data := {
		"system_prompt": _system_prompt,
		"messages": to_storage_array()
	}

	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file:
		push_error("GodotCode: Cannot open conversation file for writing: %s" % path)
		return false

	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	_is_dirty = false
	return true


## Load conversation from file
func load_from_file() -> bool:
	var path := _get_conversation_dir().path_join("current_conversation.json")
	if not FileAccess.file_exists(path):
		return false

	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return false

	var json_text := file.get_as_text()
	file.close()

	var json := JSON.new()
	var err := json.parse(json_text)
	if err != OK:
		push_error("GodotCode: Failed to parse conversation file")
		return false

	var data: Dictionary = json.data
	_system_prompt = data.get("system_prompt", "")
	from_storage_array(data.get("messages", []))
	return true


func _get_conversation_dir() -> String:
	if _settings:
		return _settings.get_conversation_dir()
	return "user://godotcode_conversations"
