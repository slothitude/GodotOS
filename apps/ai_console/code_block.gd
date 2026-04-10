extends PanelContainer
## Syntax-highlighted code block with copy button

@onready var _lang_label: Label = $VBox/Header/LangLabel
@onready var _copy_btn: Button = $VBox/Header/CopyBtn
@onready var _code_edit: CodeEdit = $VBox/CodeText

var _code: String = ""


func _ready() -> void:
	_copy_btn.pressed.connect(_on_copy)


func setup(language: String, code: String) -> void:
	_code = code
	_lang_label.text = language if language != "" else "code"
	_code_edit.text = code
	var line_count := code.split("\n").size()
	_code_edit.custom_minimum_size.y = mini(line_count * 20 + 10, 400)


func _on_copy() -> void:
	DisplayServer.clipboard_set(_code)
	_copy_btn.text = "Copied!"
	await get_tree().create_timer(1.5).timeout
	_copy_btn.text = "Copy"
