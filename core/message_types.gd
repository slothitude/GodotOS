class_name GCMessageTypes
extends RefCounted
## Data classes for LLM API message types


class BaseMessage:
	extends RefCounted
	var role: String
	var timestamp: int  # Unix epoch msec

	func _init(p_role: String) -> void:
		role = p_role
		timestamp = Time.get_ticks_msec()

	func to_api_dict() -> Dictionary:
		push_error("to_api_dict() must be overridden")
		return {}

	func to_storage_dict() -> Dictionary:
		return {"role": role, "timestamp": timestamp}


class UserMessage:
	extends BaseMessage
	var content: String

	func _init(p_content: String) -> void:
		super._init("user")
		content = p_content

	func to_api_dict() -> Dictionary:
		return {
			"role": "user",
			"content": content
		}

	func to_storage_dict() -> Dictionary:
		var d := super.to_storage_dict()
		d["content"] = content
		return d

	static func from_storage(d: Dictionary) -> UserMessage:
		var msg := UserMessage.new(d.get("content", ""))
		msg.timestamp = d.get("timestamp", 0)
		return msg


class AssistantMessage:
	extends BaseMessage
	var text_content: String = ""
	var tool_uses: Array = []  # Array of {id, name, input}

	func _init() -> void:
		super._init("assistant")

	func add_text(text: String) -> void:
		text_content += text

	func add_tool_use(tool_use_id: String, tool_name: String, tool_input: Dictionary) -> void:
		tool_uses.append({
			"id": tool_use_id,
			"name": tool_name,
			"input": tool_input
		})

	func to_api_dict() -> Dictionary:
		var content_blocks: Array = []
		if text_content != "":
			content_blocks.append({
				"type": "text",
				"text": text_content
			})
		for tu in tool_uses:
			content_blocks.append({
				"type": "tool_use",
				"id": tu.id,
				"name": tu.name,
				"input": tu.input
			})
		return {
			"role": "assistant",
			"content": content_blocks
		}

	func to_storage_dict() -> Dictionary:
		var d := super.to_storage_dict()
		d["text_content"] = text_content
		d["tool_uses"] = tool_uses
		return d

	static func from_storage(d: Dictionary) -> AssistantMessage:
		var msg := AssistantMessage.new()
		msg.text_content = d.get("text_content", "")
		msg.tool_uses = d.get("tool_uses", [])
		msg.timestamp = d.get("timestamp", 0)
		return msg


class ToolResultMessage:
	extends BaseMessage
	var tool_use_id: String
	var content: Variant  # String for text, Array for vision content blocks
	var is_error: bool = false

	func _init(p_tool_use_id: String, p_content: Variant = "", p_is_error: bool = false) -> void:
		super._init("user")  # tool_results go in user role
		tool_use_id = p_tool_use_id
		content = p_content
		is_error = p_is_error

	func to_api_dict() -> Dictionary:
		var block_content: Variant
		if content is Array:
			# Vision content blocks — pass through directly
			block_content = content
		else:
			block_content = str(content)

		var block := {
			"type": "tool_result",
			"tool_use_id": tool_use_id,
			"content": block_content
		}
		if is_error:
			block["is_error"] = true
		return {
			"role": "user",
			"content": [block]
		}

	func to_storage_dict() -> Dictionary:
		var d := super.to_storage_dict()
		d["tool_use_id"] = tool_use_id
		d["content"] = content
		d["is_error"] = is_error
		d["msg_type"] = "tool_result"
		return d

	static func from_storage(d: Dictionary) -> ToolResultMessage:
		var msg := ToolResultMessage.new(
			d.get("tool_use_id", ""),
			d.get("content", ""),
			d.get("is_error", false)
		)
		msg.timestamp = d.get("timestamp", 0)
		return msg


class SystemMessage:
	extends RefCounted
	var content: String

	func _init(p_content: String) -> void:
		content = p_content

	func to_api_dict() -> Dictionary:
		return {"type": "text", "text": content}


## Deserialize any message from storage format
static func from_storage(d: Dictionary) -> BaseMessage:
	var msg_type = d.get("msg_type", d.get("role", ""))
	match msg_type:
		"user":
			return UserMessage.from_storage(d)
		"assistant":
			return AssistantMessage.from_storage(d)
		"tool_result":
			return ToolResultMessage.from_storage(d)
		_:
			return UserMessage.from_storage(d) if d.get("role") == "user" else null
