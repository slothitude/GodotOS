extends AcceptDialog
## Permission prompt popup for tool execution approval

var _callback: Callable

@onready var _tool_label: Label = $Content/ToolLabel
@onready var _input_text: RichTextLabel = $Content/InputText
@onready var _allow_btn: Button = $Content/ButtonRow/AllowBtn
@onready var _deny_btn: Button = $Content/ButtonRow/DenyBtn
@onready var _always_btn: Button = $Content/ButtonRow/AlwaysAllowBtn


func _ready() -> void:
	_allow_btn.pressed.connect(_on_allow)
	_deny_btn.pressed.connect(_on_deny)
	_always_btn.pressed.connect(_on_always_allow)


func setup(tool_name: String, tool_input: Dictionary, callback: Callable) -> void:
	_callback = callback
	_tool_label.text = "Tool: %s" % tool_name
	var input_text := JSON.stringify(tool_input, "\t")
	if input_text.length() > 2000:
		input_text = input_text.left(2000) + "\n..."
	_input_text.text = input_text


func _on_allow() -> void:
	if _callback.is_valid():
		_callback.call(true)
	hide()


func _on_deny() -> void:
	if _callback.is_valid():
		_callback.call(false)
	hide()


func _on_always_allow() -> void:
	if _callback.is_valid():
		_callback.call(true)
	hide()
