class_name GCApiClient
extends Node
## Multi-provider LLM API client with SSE streaming
## Supports Anthropic, OpenAI, and OpenAI-compatible endpoints.

signal stream_text_delta(text: String)
signal stream_tool_use_start(tool_name: String, tool_use_id: String)
signal stream_tool_input_delta(tool_use_id: String, partial_json: String)
signal stream_complete(usage: Dictionary, stop_reason: String)
signal stream_error(error: Dictionary)

var _settings: GCSettings
var _http_request: HTTPRequest
var _is_streaming: bool = false
var _stream_buffer: String = ""
var _current_tool_inputs: Dictionary = {}  # tool_use_id -> accumulated JSON string

# SSE parsing state
var _event_type: String = ""
var _event_data: String = ""


func send_message_streaming(messages: Array, system_prompt: String, tools: Array) -> void:
	if _is_streaming:
		stream_error.emit({"message": "Already streaming"})
		return

	if not _settings:
		stream_error.emit({"message": "Settings not initialized"})
		return

	var api_key := _settings.get_api_key()
	if api_key == "":
		stream_error.emit({"message": "API key not set. Open Settings to configure."})
		return

	_is_streaming = true
	_stream_buffer = ""
	_current_tool_inputs.clear()

	var provider := _settings.get_provider()
	var headers := _build_headers(provider, api_key)
	var url := _build_url(provider)
	var body := _build_body(provider, messages, system_prompt, tools)

	if not _http_request:
		_http_request = HTTPRequest.new()
		_http_request.request_completed.connect(_on_request_completed)
		add_child(_http_request)

	var json_body := JSON.stringify(body)
	print("[APIClient] POST %s (provider=%s, model=%s, msgs=%d)" % [url, provider, _settings.get_model(), messages.size()])
	var err := _http_request.request(url, headers, HTTPClient.METHOD_POST, json_body)
	if err != OK:
		_is_streaming = false
		stream_error.emit({"message": "HTTP request failed: %d" % err})


func send_message_sync(messages: Array, system_prompt: String, tools: Array) -> void:
	## Non-streaming request — collects full response then emits signals.
	if _is_streaming:
		stream_error.emit({"message": "Already streaming"})
		return

	var api_key := _settings.get_api_key()
	if api_key == "":
		stream_error.emit({"message": "API key not set"})
		return

	_is_streaming = true

	var provider := _settings.get_provider()
	var headers := _build_headers(provider, api_key)
	var url := _build_url(provider)
	var body := _build_body(provider, messages, system_prompt, tools)
	body["stream"] = false

	if not _http_request:
		_http_request = HTTPRequest.new()
		_http_request.request_completed.connect(_on_sync_request_completed)
		add_child(_http_request)

	var json_body := JSON.stringify(body)
	_http_request.request(url, headers, HTTPClient.METHOD_POST, json_body)


# --- Provider-specific header builders ---

func _build_headers(provider: String, api_key: String) -> PackedStringArray:
	match provider:
		"anthropic":
			return PackedStringArray([
				"Content-Type: application/json",
				"x-api-key: %s" % api_key,
				"anthropic-version: 2023-06-01",
				"Accept: text/event-stream"
			])
		_, _:
			# OpenAI and OpenAI-compatible use Bearer auth
			return PackedStringArray([
				"Content-Type: application/json",
				"Authorization: Bearer %s" % api_key,
				"Accept: text/event-stream"
			])


# --- Provider-specific URL builders ---

func _build_url(provider: String) -> String:
	var base := _settings.get_base_url()
	match provider:
		"anthropic":
			return base + "/v1/messages"
		_, _:
			return base + "/v1/chat/completions"


# --- Provider-specific request body builders ---

func _build_body(provider: String, messages: Array, system_prompt: String, tools: Array) -> Dictionary:
	match provider:
		"anthropic":
			return _build_anthropic_body(messages, system_prompt, tools)
		_, _:
			return _build_openai_body(messages, system_prompt, tools)


func _build_anthropic_body(messages: Array, system_prompt: String, tools: Array) -> Dictionary:
	var api_messages := _convert_messages_anthropic(messages)
	var body := {
		"model": _settings.get_model(),
		"max_tokens": _settings.get_max_tokens(),
		"stream": true,
		"messages": api_messages
	}
	if system_prompt != "":
		body["system"] = system_prompt
	var api_tools := _convert_tools_anthropic(tools)
	if api_tools.size() > 0:
		body["tools"] = api_tools
	return body


func _build_openai_body(messages: Array, system_prompt: String, tools: Array) -> Dictionary:
	var api_messages := _convert_messages_openai(messages, system_prompt)
	var body := {
		"model": _settings.get_model(),
		"max_tokens": _settings.get_max_tokens(),
		"stream": true,
		"messages": api_messages
	}
	if _settings.get_temperature() > 0.0:
		body["temperature"] = _settings.get_temperature()
	var api_tools := _convert_tools_openai(tools)
	if api_tools.size() > 0:
		body["tools"] = api_tools
	return body


# --- Message conversion ---

func _convert_messages_anthropic(messages: Array) -> Array:
	var result: Array = []
	var pending_results: Array = []

	for msg in messages:
		if msg is GCMessageTypes.ToolResultMessage:
			pending_results.append(msg)
		else:
			if pending_results.size() > 0:
				result.append(_merge_tool_results_anthropic(pending_results))
				pending_results.clear()
			if msg is GCMessageTypes.UserMessage:
				result.append(msg.to_api_dict())
			elif msg is GCMessageTypes.AssistantMessage:
				var d: Dictionary = msg.to_api_dict()
				if (d.get("content") as Array).size() > 0:
					result.append(d)

	if pending_results.size() > 0:
		result.append(_merge_tool_results_anthropic(pending_results))

	return result


func _merge_tool_results_anthropic(results: Array) -> Dictionary:
	var blocks: Array = []
	for r in results:
		var block := {"type": "tool_result", "tool_use_id": r.tool_use_id, "content": r.content}
		if r.is_error:
			block["is_error"] = true
		blocks.append(block)
	return {"role": "user", "content": blocks}


func _convert_messages_openai(messages: Array, system_prompt: String) -> Array:
	var result: Array = []

	if system_prompt != "":
		result.append({"role": "system", "content": system_prompt})

	for msg in messages:
		if msg is GCMessageTypes.UserMessage:
			result.append({"role": "user", "content": msg.content})
		elif msg is GCMessageTypes.AssistantMessage:
			var m := {"role": "assistant"}
			if msg.text_content != "":
				m["content"] = msg.text_content
			else:
				m["content"] = null
			if msg.tool_uses.size() > 0:
				var tool_calls: Array = []
				for tu in msg.tool_uses:
					tool_calls.append({
						"id": tu.id,
						"type": "function",
						"function": {
							"name": tu.name,
							"arguments": JSON.stringify(tu.input)
						}
					})
				m["tool_calls"] = tool_calls
			result.append(m)
		elif msg is GCMessageTypes.ToolResultMessage:
			result.append({
				"role": "tool",
				"tool_call_id": msg.tool_use_id,
				"content": msg.content
			})

	return result


# --- Tool conversion ---

func _convert_tools_anthropic(tools: Array) -> Array:
	var result: Array = []
	for tool in tools:
		if tool is GCBaseTool:
			result.append(tool.to_tool_definition())
	return result


func _convert_tools_openai(tools: Array) -> Array:
	var result: Array = []
	for tool in tools:
		if tool is GCBaseTool:
			result.append({
				"type": "function",
				"function": {
					"name": tool.tool_name,
					"description": tool.description,
					"parameters": {
						"type": "object",
						"properties": tool.input_schema
					}
				}
			})
	return result


# --- Response handlers ---

func _on_request_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_is_streaming = false

	if result != HTTPRequest.RESULT_SUCCESS:
		var msg := "Request failed (result=%d)" % result
		print("[APIClient] ERROR: %s" % msg)
		stream_error.emit({"message": msg})
		return

	if code >= 400:
		var body_text := body.get_string_from_utf8()
		var error_msg := "API error (HTTP %d)" % code
		var json := JSON.new()
		if json.parse(body_text) == OK:
			var data: Dictionary = json.data
			if data.has("error"):
				var err = data.error
				if err is Dictionary:
					error_msg = str(err.get("message", error_msg))
				else:
					error_msg = str(err)
		print("[APIClient] ERROR: %s" % error_msg)
		print("[APIClient] Response body: %s" % body_text.left(500))
		stream_error.emit({"message": error_msg, "code": code})
		return

	# Parse SSE response
	var response_text := body.get_string_from_utf8()
	var provider := _settings.get_provider()
	match provider:
		"anthropic":
			_parse_anthropic_sse(response_text)
		_, _:
			_parse_openai_sse(response_text)


func _on_sync_request_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_is_streaming = false

	if result != HTTPRequest.RESULT_SUCCESS:
		stream_error.emit({"message": "Request failed (result=%d)" % result})
		return

	if code >= 400:
		var body_text := body.get_string_from_utf8()
		stream_error.emit({"message": "API error (HTTP %d): %s" % [code, body_text]})
		return

	var response_text := body.get_string_from_utf8()
	var provider := _settings.get_provider()
	match provider:
		"anthropic":
			_handle_anthropic_full_response(response_text)
		_, _:
			_handle_openai_full_response(response_text)


func _handle_anthropic_full_response(response_text: String) -> void:
	var json := JSON.new()
	if json.parse(response_text) != OK:
		return
	var data: Dictionary = json.data
	var content_blocks: Array = data.get("content", [])
	for block in content_blocks:
		if block.get("type") == "text":
			stream_text_delta.emit(block.get("text", ""))
		elif block.get("type") == "tool_use":
			stream_tool_use_start.emit(block.get("name", ""), block.get("id", ""))
			var input_json := JSON.stringify(block.get("input", {}))
			stream_tool_input_delta.emit(block.get("id", ""), input_json)
	var usage: Dictionary = data.get("usage", {})
	var stop_reason: String = data.get("stop_reason", "")
	stream_complete.emit(usage, stop_reason)


func _handle_openai_full_response(response_text: String) -> void:
	var json := JSON.new()
	if json.parse(response_text) != OK:
		return
	var data: Dictionary = json.data
	var choices: Array = data.get("choices", [])
	if choices.size() == 0:
		stream_complete.emit({}, "")
		return
	var choice: Dictionary = choices[0]
	var message: Dictionary = choice.get("message", {})
	if message.get("content") != null:
		stream_text_delta.emit(str(message.get("content", "")))
	if message.has("tool_calls"):
		for tc in message.get("tool_calls", []):
			var func_data: Dictionary = tc.get("function", {})
			stream_tool_use_start.emit(func_data.get("name", ""), tc.get("id", ""))
			stream_tool_input_delta.emit(tc.get("id", ""), func_data.get("arguments", "{}"))
	var usage: Dictionary = data.get("usage", {})
	stream_complete.emit(usage, choice.get("finish_reason", ""))


# --- SSE parsers ---

func _parse_anthropic_sse(text: String) -> void:
	var lines := text.split("\n")
	_event_type = ""
	_event_data = ""

	for line in lines:
		if line == "":
			# Empty line = end of event
			if _event_type != "":
				_process_anthropic_event(_event_type, _event_data)
				_event_type = ""
				_event_data = ""
			continue

		if line.begins_with("event:"):
			_event_type = line.substr(6).strip_edges()
		elif line.begins_with("data:"):
			var data_str := line.substr(5).strip_edges()
			if _event_data != "":
				_event_data += "\n"
			_event_data += data_str


func _process_anthropic_event(event_type: String, data_str: String) -> void:
	var json := JSON.new()
	if json.parse(data_str) != OK:
		return

	var data: Dictionary = json.data

	match event_type:
		"message_start":
			pass

		"content_block_start":
			var block: Dictionary = data.get("content_block", {})
			if block.get("type") == "tool_use":
				var tool_name: String = block.get("name", "")
				var tool_id: String = block.get("id", "")
				_current_tool_inputs[tool_id] = ""
				stream_tool_use_start.emit(tool_name, tool_id)

		"content_block_delta":
			var delta: Dictionary = data.get("delta", {})
			var delta_type: String = delta.get("type", "")
			match delta_type:
				"text_delta":
					stream_text_delta.emit(delta.get("text", ""))
				"input_json_delta":
					var tool_id: String = ""
					var index: int = data.get("index", 0)
					var keys := _current_tool_inputs.keys()
					if index < keys.size():
						tool_id = str(keys[index])
					var partial: String = delta.get("partial_json", "")
					if tool_id != "" and _current_tool_inputs.has(tool_id):
						_current_tool_inputs[tool_id] += partial
					stream_tool_input_delta.emit(tool_id, partial)

		"content_block_stop":
			pass

		"message_delta":
			pass

		"message_stop":
			var usage: Dictionary = {}
			if data.has("usage"):
				usage = data.get("usage", {})
			stream_complete.emit(usage, data.get("delta", {}).get("stop_reason", ""))

		"ping":
			pass

		"error":
			stream_error.emit(data.get("error", {"message": "SSE error"}))


func _parse_openai_sse(text: String) -> void:
	var lines := text.split("\n")

	for line in lines:
		if not line.begins_with("data:"):
			continue

		var data_str := line.substr(5).strip_edges()
		if data_str == "[DONE]":
			# Stream complete
			for tool_id in _current_tool_inputs:
				var raw_json: String = _current_tool_inputs[tool_id]
				stream_tool_input_delta.emit(tool_id, raw_json)
			stream_complete.emit({}, "stop")
			return

		var json := JSON.new()
		if json.parse(data_str) != OK:
			continue

		var data: Dictionary = json.data
		var choices: Array = data.get("choices", [])
		if choices.size() == 0:
			continue

		var choice: Dictionary = choices[0]
		var delta: Dictionary = choice.get("delta", {})

		# Text content
		if delta.has("content") and delta.get("content") != null:
			stream_text_delta.emit(str(delta.get("content", "")))

		# Tool calls
		if delta.has("tool_calls"):
			var tool_calls: Array = delta.get("tool_calls", [])
			for tc in tool_calls:
				var tc_id: String = str(tc.get("id", ""))
				if tc.has("function"):
					var func_data: Dictionary = tc.get("function", {})
					if tc_id != "":
						# First chunk for this tool call — emit start
						var func_name: String = func_data.get("name", "")
						if func_name != "":
							_current_tool_inputs[tc_id] = ""
							stream_tool_use_start.emit(func_name, tc_id)
					var partial_args: String = str(func_data.get("arguments", ""))
					if tc_id != "" and _current_tool_inputs.has(tc_id):
						_current_tool_inputs[tc_id] += partial_args
					stream_tool_input_delta.emit(tc_id, partial_args)
