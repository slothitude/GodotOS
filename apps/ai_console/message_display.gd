extends VBoxContainer
## Renders a single chat message with role label and content

@onready var _role_label: Label = $RoleLabel
@onready var _content: RichTextLabel = $Content


func setup(role: String, text: String) -> void:
	match role:
		"user":
			_role_label.text = "You"
			_role_label.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
			_content.add_theme_color_override("default_color", Color(0.85, 0.92, 1.0))
		"assistant":
			_role_label.text = "GodotOS"
			_role_label.add_theme_color_override("font_color", Color(0.7, 0.9, 0.7))
			_content.add_theme_color_override("default_color", Color(1.0, 1.0, 1.0))
		"tool":
			_role_label.text = "Tool"
			_role_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.5))
			_content.add_theme_color_override("default_color", Color(0.8, 0.8, 0.6))
		"error":
			_role_label.text = "Error"
			_role_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
			_content.add_theme_color_override("default_color", Color(1.0, 0.5, 0.5))
		"system":
			_role_label.text = "System"
			_role_label.add_theme_color_override("font_color", Color(0.9, 0.8, 0.5))
			_content.add_theme_color_override("default_color", Color(0.9, 0.85, 0.6))

	_content.text = _markdown_to_bbcode(text)


func _markdown_to_bbcode(text: String) -> String:
	var result := text
	var regex := RegEx.new()
	regex.compile("\\*\\*(.+?)\\*\\*")
	result = regex.sub(result, "[b]$1[/b]", true)
	regex.compile("\\*(.+?)\\*")
	result = regex.sub(result, "[i]$1[/i]", true)
	regex.compile("`(.+?)`")
	result = regex.sub(result, "[code]$1[/code]", true)
	return result
