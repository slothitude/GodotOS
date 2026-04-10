extends VBoxContainer
## AI Console — main chat interface for GodotOS
## Adapted from GodotCode chat_panel.gd — removed @tool, EditorPlugin refs

var _query_engine: GCQueryEngine
var _settings: GCSettings
var _conversation_history: GCConversationHistory
var _cost_tracker: GCCostTracker
var _settings_dialog: AcceptDialog
var _streaming_label: RichTextLabel
var _is_streaming: bool = false

@onready var _send_btn: Button = $InputArea/SendBtn
@onready var _input_field: TextEdit = $InputArea/InputField
@onready var _message_list: VBoxContainer = $MessageContainer/MessageList
@onready var _message_container: ScrollContainer = $MessageContainer
@onready var _status_label: Label = $StatusBar/StatusLabel
@onready var _cost_label: Label = $Header/CostLabel
@onready var _settings_btn: Button = $Header/SettingsBtn


func _ready() -> void:
	_send_btn.pressed.connect(_on_send)
	_settings_btn.pressed.connect(_on_settings)
	_input_field.gui_input.connect(_on_input_gui_input)

	# Register as singleton so CommandBus can route AI queries here
	Engine.register_singleton("AIConsole", self)

	# Wire query engine signals if available
	if _query_engine:
		_wire_query_engine()

	_load_conversation()


func _wire_query_engine() -> void:
	_query_engine.message_received.connect(_on_message_received)
	_query_engine.stream_text_delta.connect(_on_stream_delta)
	_query_engine.stream_tool_call_received.connect(_on_tool_call)
	_query_engine.query_complete.connect(_on_query_complete)
	_query_engine.query_error.connect(_on_query_error)
	_query_engine.permission_requested.connect(_on_permission_requested)
	_query_engine.status_update.connect(_on_status_update)


## Called by shell.gd after boot to wire in GC subsystems
func setup(settings: GCSettings, query_engine: GCQueryEngine, conversation_history: GCConversationHistory, cost_tracker: GCCostTracker) -> void:
	_settings = settings
	_query_engine = query_engine
	_conversation_history = conversation_history
	_cost_tracker = cost_tracker
	_wire_query_engine()
	_load_conversation()


## Called by CommandBus for AI commands
func run_query(prompt: String, params: Dictionary = {}) -> Dictionary:
	if not _query_engine:
		return {"error": "Query engine not initialized"}
	_query_engine.submit_message(prompt)
	return {"ok": true}


func _on_input_gui_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.keycode == KEY_ENTER and not key_event.shift_pressed:
			if key_event.pressed:
				_on_send()
				_input_field.accept_event()


func _on_send() -> void:
	var text := _input_field.text.strip_edges()
	if text == "" or _is_streaming:
		return

	_input_field.text = ""

	# Add user message to display
	_add_message_bubble("user", text)

	# Submit to query engine
	_is_streaming = true
	_send_btn.disabled = true
	_query_engine.submit_message(text)


func _on_message_received(message: Dictionary) -> void:
	if message.get("role") == "assistant":
		var content = message.get("content", "")
		if content is String and content != "":
			if _streaming_label:
				_streaming_label = null
			else:
				_add_message_bubble("assistant", content)


func _on_stream_delta(text: String) -> void:
	if not _streaming_label:
		_streaming_label = _create_message_label("assistant")
	_status_label.text = "Streaming..."
	_streaming_label.text += text
	await get_tree().process_frame
	if _streaming_label and _streaming_label.is_inside_tree():
		_message_container.ensure_control_visible(_streaming_label)


func _on_tool_call(tool_name: String, tool_input: Dictionary) -> void:
	_add_message_bubble("tool", "[Tool: %s]" % tool_name)
	_status_label.text = "Running: %s" % tool_name


func _on_query_complete(result: Dictionary) -> void:
	_is_streaming = false
	_streaming_label = null
	_send_btn.disabled = false
	_status_label.text = "Ready"
	if _cost_tracker:
		var cost := _cost_tracker.get_session_cost()
		_cost_label.text = "$%.2f" % cost
	_save_conversation()


func _on_status_update(message: String) -> void:
	_status_label.text = message


func _on_query_error(error: Dictionary) -> void:
	_is_streaming = false
	_streaming_label = null
	_send_btn.disabled = false
	_status_label.text = "Error"
	var error_msg := str(error.get("message", "Unknown error"))
	_add_message_bubble("error", error_msg)


func _on_permission_requested(tool_name: String, tool_input: Dictionary, callback: Callable) -> void:
	var dialog := preload("res://apps/ai_console/tool_approval_dialog.tscn").instantiate()
	add_child(dialog)
	dialog.setup(tool_name, tool_input, callback)
	dialog.popup_centered(Vector2i(500, 300))


func _add_message_bubble(role: String, text: String) -> void:
	var label := _create_message_label(role)
	label.text = text
	await get_tree().process_frame
	if is_instance_valid(_message_container):
		_message_container.ensure_control_visible(label)


func _create_message_label(role: String) -> RichTextLabel:
	var label := RichTextLabel.new()
	label.fit_content = true
	label.scroll_following = true
	label.bbcode_enabled = true
	label.custom_minimum_size = Vector2(0, 40)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	match role:
		"user":
			label.add_theme_color_override("default_color", Color(0.8, 0.9, 1.0))
		"assistant":
			label.add_theme_color_override("default_color", Color(1.0, 1.0, 1.0))
		"tool":
			label.add_theme_color_override("default_color", Color(0.7, 0.9, 0.7))
		"error":
			label.add_theme_color_override("default_color", Color(1.0, 0.5, 0.5))
		"system":
			label.add_theme_color_override("default_color", Color(0.9, 0.8, 0.5))

	_message_list.add_child(label)
	return label


func _on_settings() -> void:
	if not _settings_dialog:
		_settings_dialog = preload("res://apps/ai_console/settings_dialog.tscn").instantiate()
		_settings_dialog._settings = _settings
		add_child(_settings_dialog)
	_settings_dialog.popup_centered(Vector2i(450, 400))


func _load_conversation() -> void:
	if _conversation_history and _conversation_history.load_from_file():
		for msg in _conversation_history.get_display_messages():
			_add_message_bubble(msg.role, msg.content)


func _save_conversation() -> void:
	if _conversation_history:
		_conversation_history.save_to_file()
