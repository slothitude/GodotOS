class_name GCTheme
extends RefCounted
## Color theme definitions for GodotOS

const DARK := {
	"bg": Color(0.12, 0.12, 0.15),
	"fg": Color(0.9, 0.9, 0.9),
	"user_bubble": Color(0.15, 0.2, 0.3),
	"assistant_bubble": Color(0.18, 0.18, 0.22),
	"tool_bubble": Color(0.15, 0.18, 0.15),
	"error_bubble": Color(0.25, 0.12, 0.12),
	"system_bubble": Color(0.2, 0.18, 0.12),
	"border": Color(0.3, 0.3, 0.35),
	"accent": Color(0.4, 0.6, 1.0),
	"link": Color(0.5, 0.7, 1.0),
	"code_bg": Color(0.1, 0.1, 0.14),
	"input_bg": Color(0.14, 0.14, 0.18),
	"button_bg": Color(0.2, 0.2, 0.25),
	"button_hover": Color(0.25, 0.25, 0.3),
}

const LIGHT := {
	"bg": Color(0.95, 0.95, 0.97),
	"fg": Color(0.15, 0.15, 0.18),
	"user_bubble": Color(0.85, 0.9, 0.98),
	"assistant_bubble": Color(0.92, 0.92, 0.94),
	"tool_bubble": Color(0.88, 0.93, 0.88),
	"error_bubble": Color(0.98, 0.88, 0.88),
	"system_bubble": Color(0.95, 0.93, 0.85),
	"border": Color(0.75, 0.75, 0.78),
	"accent": Color(0.3, 0.5, 0.9),
	"link": Color(0.2, 0.4, 0.8),
	"code_bg": Color(0.92, 0.92, 0.95),
	"input_bg": Color(1.0, 1.0, 1.0),
	"button_bg": Color(0.88, 0.88, 0.9),
	"button_hover": Color(0.82, 0.82, 0.85),
}


static func get_theme(theme_name: String) -> Dictionary:
	match theme_name:
		"light":
			return LIGHT
		_:
			return DARK


static func apply_to_control(control: Control, theme_name: String) -> void:
	var colors := get_theme(theme_name)
	var style := StyleBoxFlat.new()
	style.bg_color = colors.bg
	style.border_color = colors.border
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	control.add_theme_stylebox_override("panel", style)
