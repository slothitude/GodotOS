class_name GCQueryEngine
extends RefCounted
## Core query loop: send -> stream -> parse tool calls -> execute -> repeat

enum State { IDLE, STREAMING, TOOL_EXECUTING, COMPLETE, ERROR }

signal message_received(message: Dictionary)
signal stream_text_delta(text: String)
signal stream_tool_call_received(tool_name: String, tool_input: Dictionary)
signal query_complete(result: Dictionary)
signal query_error(error: Dictionary)
signal permission_requested(tool_name: String, tool_input: Dictionary, callback: Callable)
signal status_update(message: String)

var state: State = State.IDLE
var _api_client: GCApiClient
var _tool_registry: GCToolRegistry
var _conversation_history: GCConversationHistory
var _permission_manager: GCPermissionManager
var _cost_tracker: GCCostTracker
var _context_manager: GCContextManager
var _settings: GCSettings

var _pending_tool_calls: Array = []  # {name, id, input}
var _current_assistant: GCMessageTypes.AssistantMessage
var _iteration_count: int = 0
var _max_iterations: int = 50
var _consecutive_tool_failures: int = 0
var _max_consecutive_failures: int = 3
var _tool_failed_this_round: bool = false


func submit_message(prompt: String) -> void:
	if state != State.IDLE:
		query_error.emit({"message": "Query engine busy (state=%d)" % state})
		return

	# Add user message if non-empty
	if prompt != "":
		_conversation_history.add_user_message(prompt)

	# Build system prompt with context
	var system_prompt := _build_system_prompt()

	_iteration_count = 0
	_consecutive_tool_failures = 0
	_start_stream(system_prompt)


func _start_stream(system_prompt: String) -> void:
	state = State.STREAMING
	_current_assistant = _conversation_history.add_assistant_message()
	_pending_tool_calls.clear()
	status_update.emit("Thinking...")

	# Pass internal message objects — the API client converts per provider
	var messages := _conversation_history.get_messages()
	var tools_array: Array = _tool_registry.get_all_tools().values()

	# Connect API signals (will auto-disconnect when complete)
	if not _api_client.stream_text_delta.is_connected(_on_stream_text):
		_api_client.stream_text_delta.connect(_on_stream_text)
	if not _api_client.stream_tool_use_start.is_connected(_on_stream_tool_start):
		_api_client.stream_tool_use_start.connect(_on_stream_tool_start)
	if not _api_client.stream_tool_input_delta.is_connected(_on_stream_tool_input):
		_api_client.stream_tool_input_delta.connect(_on_stream_tool_input)
	if not _api_client.stream_complete.is_connected(_on_stream_complete):
		_api_client.stream_complete.connect(_on_stream_complete)
	if not _api_client.stream_error.is_connected(_on_stream_error):
		_api_client.stream_error.connect(_on_stream_error)

	_api_client.send_message_streaming(messages, system_prompt, tools_array)


func _on_stream_text(text: String) -> void:
	if _current_assistant:
		_current_assistant.add_text(text)
	stream_text_delta.emit(text)


func _on_stream_tool_start(tool_name: String, tool_use_id: String) -> void:
	_pending_tool_calls.append({"name": tool_name, "id": tool_use_id, "input": {}})


func _on_stream_tool_input(tool_use_id: String, partial_json: String) -> void:
	# Accumulate tool input JSON — parse on complete
	for tc in _pending_tool_calls:
		if tc.id == tool_use_id:
			tc["_raw_input"] = tc.get("_raw_input", "") + partial_json
			break


func _on_stream_complete(usage: Dictionary, stop_reason: String) -> void:
	print("[QueryEngine] Stream complete (stop=%s, tools=%d, text=%d chars)" % [stop_reason, _pending_tool_calls.size(), _current_assistant.text_content.length() if _current_assistant else 0])
	if _pending_tool_calls.size() > 0:
		var names: Array = []
		for tc in _pending_tool_calls:
			names.append(tc.name)
		print("[QueryEngine] Tool calls: %s" % str(names))
	# Track costs
	if _cost_tracker:
		_cost_tracker.add_usage(usage)

	# Parse accumulated tool input JSON
	for tc in _pending_tool_calls:
		var raw: String = tc.get("_raw_input", "")
		if raw != "":
			var json := JSON.new()
			if json.parse(raw) == OK:
				tc.input = json.data
			else:
				tc.input = {}

	# Disconnect signals
	if _api_client:
		if _api_client.stream_text_delta.is_connected(_on_stream_text):
			_api_client.stream_text_delta.disconnect(_on_stream_text)
		if _api_client.stream_tool_use_start.is_connected(_on_stream_tool_start):
			_api_client.stream_tool_use_start.disconnect(_on_stream_tool_start)
		if _api_client.stream_tool_input_delta.is_connected(_on_stream_tool_input):
			_api_client.stream_tool_input_delta.disconnect(_on_stream_tool_input)
		if _api_client.stream_complete.is_connected(_on_stream_complete):
			_api_client.stream_complete.disconnect(_on_stream_complete)
		if _api_client.stream_error.is_connected(_on_stream_error):
			_api_client.stream_error.disconnect(_on_stream_error)

	# Finalize current assistant message
	if _current_assistant:
		for tc in _pending_tool_calls:
			_current_assistant.add_tool_use(tc.id, tc.name, tc.input)
		message_received.emit({"role": "assistant", "content": _current_assistant.text_content})

	# Process tool calls or complete
	if _pending_tool_calls.size() > 0:
		state = State.TOOL_EXECUTING
		_execute_tool_calls_async()
	else:
		state = State.COMPLETE
		query_complete.emit({"usage": usage, "stop_reason": stop_reason})


func _on_stream_error(error: Dictionary) -> void:
	state = State.ERROR
	print("[QueryEngine] Stream error: %s" % str(error))
	query_error.emit(error)


func _execute_tool_calls() -> void:
	_iteration_count += 1
	if _iteration_count > _max_iterations:
		state = State.ERROR
		query_error.emit({"message": "Max iterations exceeded (%d)" % _max_iterations})
		return

	for tc in _pending_tool_calls:
		var tool: GCBaseTool = _tool_registry.get_tool(tc.name)

		if not tool:
			_conversation_history.add_tool_result(tc.id, "Unknown tool: %s" % tc.name, true)
			continue

		# Check permissions
		var perm := tool.check_permissions(tc.input, _build_context())
		var behavior: String = perm.get("behavior", "ask")

		match behavior:
			"deny":
				_conversation_history.add_tool_result(tc.id, "Permission denied: " + perm.get("message", ""), true)
			"ask":
				var mode := _permission_manager.get_current_mode() if _permission_manager else "default"
				if mode == "bypass":
					_execute_single_tool(tool, tc)
				else:
					permission_requested.emit(tc.name, tc.input, func(approved: bool):
						if approved:
							_execute_single_tool(tool, tc)
						else:
							_conversation_history.add_tool_result(tc.id, "User denied permission", true)
					)
			"allow":
				_execute_single_tool(tool, tc)

	_pending_tool_calls.clear()

	# Re-query with tool results
	var system_prompt := _build_system_prompt()
	_start_stream(system_prompt)


func _execute_tool_calls_async() -> void:
	_iteration_count += 1
	if _iteration_count > _max_iterations:
		state = State.ERROR
		query_error.emit({"message": "Max iterations exceeded (%d)" % _max_iterations})
		return

	status_update.emit("Executing tools...")
	_tool_failed_this_round = false
	for tc in _pending_tool_calls:
		var tool: GCBaseTool = _tool_registry.get_tool(tc.name)

		if not tool:
			_conversation_history.add_tool_result(tc.id, "Unknown tool: %s" % tc.name, true)
			_tool_failed_this_round = true
			continue

		# Check permissions
		var perm := tool.check_permissions(tc.input, _build_context())
		var behavior: String = perm.get("behavior", "ask")

		match behavior:
			"deny":
				_conversation_history.add_tool_result(tc.id, "Permission denied: " + perm.get("message", ""), true)
			"ask":
				var mode := _permission_manager.get_current_mode() if _permission_manager else "default"
				if mode == "bypass":
					await _execute_single_tool_async(tool, tc)
				else:
					permission_requested.emit(tc.name, tc.input, func(approved: bool):
						if approved:
							await _execute_single_tool_async(tool, tc)
						else:
							_conversation_history.add_tool_result(tc.id, "User denied permission", true)
					)
			"allow":
				await _execute_single_tool_async(tool, tc)

	# Track consecutive failures
	if _tool_failed_this_round:
		_consecutive_tool_failures += 1
	else:
		_consecutive_tool_failures = 0
	_pending_tool_calls.clear()

	# Stop retrying after too many consecutive failures
	if _consecutive_tool_failures >= _max_consecutive_failures:
		print("[QueryEngine] %d consecutive tool failures — stopping" % _consecutive_tool_failures)
		if _current_assistant:
			_current_assistant.add_text("\n\n[Tool execution repeatedly failed — bridge may be offline or tools unavailable.]")
		message_received.emit({"role": "assistant", "content": _current_assistant.text_content if _current_assistant else ""})
		_conversation_history.save_to_file()
		state = State.COMPLETE
		query_complete.emit({"usage": {}, "stop_reason": "tool_failure"})
		return

	# Re-query with tool results
	var system_prompt := _build_system_prompt()
	_start_stream(system_prompt)


func _execute_single_tool(tool: GCBaseTool, tool_call: Dictionary) -> void:
	stream_tool_call_received.emit(tool_call.name, tool_call.input)
	var result := tool.execute(tool_call.input, _build_context())

	# Check if tool returned vision content
	if tool.has_vision_result(result) and result.get("success", false):
		# Build vision content blocks for the API
		var vision_blocks: Array = [
			{
				"type": "image",
				"source": {
					"type": "base64",
					"media_type": result.get("media_type", "image/png"),
					"data": result.get("vision_data", "")
				}
			},
			{
				"type": "text",
				"text": str(result.get("data", ""))
			}
		]
		_conversation_history.add_tool_result(tool_call.id, vision_blocks, false)
	else:
		var tool_result := tool.to_api_result(result, tool_call.id)
		_conversation_history.add_tool_result(
			tool_call.id,
			tool_result.get("content", ""),
			tool_result.get("is_error", false)
		)


func _execute_single_tool_async(tool: GCBaseTool, tool_call: Dictionary) -> void:
	stream_tool_call_received.emit(tool_call.name, tool_call.input)
	var result = await tool.execute(tool_call.input, _build_context())

	var success: bool = result.get("success", false) if result is Dictionary else false

	# Check if tool returned vision content
	if tool.has_vision_result(result) and success:
		var vision_blocks: Array = [
			{
				"type": "image",
				"source": {
					"type": "base64",
					"media_type": result.get("media_type", "image/png"),
					"data": result.get("vision_data", "")
				}
			},
			{
				"type": "text",
				"text": str(result.get("data", ""))
			}
		]
		_conversation_history.add_tool_result(tool_call.id, vision_blocks, false)
	else:
		var tool_result := tool.to_api_result(result, tool_call.id)
		_conversation_history.add_tool_result(
			tool_call.id,
			tool_result.get("content", ""),
			tool_result.get("is_error", false)
		)
	if not success:
		_tool_failed_this_round = true
		print("[QueryEngine] Tool '%s' failed: %s" % [tool_call.name, str(result.get("error", "unknown"))])


func _build_system_prompt() -> String:
	var prompt := ""
	if _context_manager:
		prompt = _context_manager.build_system_prompt()
	if _conversation_history:
		var sp := _conversation_history.get_system_prompt()
		if sp != "":
			if prompt != "":
				prompt += "\n\n"
			prompt += sp
	return prompt


func _build_context() -> Dictionary:
	return {
		"project_path": ProjectSettings.globalize_path("res://"),
		"conversation_history": _conversation_history,
		"tool_registry": _tool_registry,
		"settings": _settings,
	}
