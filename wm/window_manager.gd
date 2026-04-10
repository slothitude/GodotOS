extends Node
## Window Manager — floating window management for GodotOS
## Instantiates scenes, wraps in window chrome (title bar + close button)

var _windows: Dictionary = {}  # id -> {scene_path, params, node, frame}
var _next_id: int = 0
var _focused_id: String = ""

signal window_opened(id: String, params: Dictionary)
signal window_closed(id: String)
signal window_focused(id: String)


func _ready() -> void:
	Engine.register_singleton("WindowManager", self)


func open_app(scene_path: String, params: Dictionary = {}) -> String:
	_next_id += 1
	var id := "win_%03d" % _next_id
	var title: String = params.get("title", "Untitled")
	var position: Vector2 = params.get("position", Vector2(100 + (_next_id * 30) % 200, 80 + (_next_id * 30) % 150))
	var size: Vector2 = params.get("size", Vector2(600, 500))

	# Try to load and instantiate the scene
	var app_node: Control = null
	if scene_path != "" and ResourceLoader.exists(scene_path):
		var scene := load(scene_path) as PackedScene
		if scene:
			app_node = scene.instantiate()

	# Create window frame
	var frame := PanelContainer.new()
	frame.name = "WindowFrame_%s" % id
	frame.position = position
	frame.size = size
	frame.custom_minimum_size = Vector2(200, 150)

	# Style the frame
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.14, 0.14, 0.18)
	style.border_color = Color(0.3, 0.3, 0.38)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	frame.add_theme_stylebox_override("panel", style)

	# Inner VBox: title bar + content
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.add_child(vbox)

	# Title bar
	var title_bar := HBoxContainer.new()
	title_bar.custom_minimum_size = Vector2(0, 28)
	vbox.add_child(title_bar)

	var title_label := Label.new()
	title_label.text = "  %s" % title
	title_label.add_theme_color_override("font_color", Color(0.8, 0.85, 0.95))
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_bar.add_child(title_label)

	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.custom_minimum_size = Vector2(28, 24)
	close_btn.flat = true
	close_btn.add_theme_color_override("font_color", Color(0.8, 0.4, 0.4))
	close_btn.pressed.connect(func(): close_window(id))
	title_bar.add_child(close_btn)

	# Separator
	var sep := HSeparator.new()
	vbox.add_child(sep)

	# Content area — add the actual app scene if loaded
	if app_node:
		app_node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		app_node.size_flags_vertical = Control.SIZE_EXPAND_FILL
		vbox.add_child(app_node)
	else:
		# Placeholder if scene doesn't exist yet
		var placeholder := Label.new()
		placeholder.text = "  Loading: %s" % scene_path
		placeholder.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))
		placeholder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		placeholder.size_flags_vertical = Control.SIZE_EXPAND_FILL
		vbox.add_child(placeholder)

	# Add to scene tree (the wallpaper's parent is Shell, we add alongside it)
	get_parent().add_child(frame)
	# Move frame after all existing children (but before Taskbar)
	var taskbar_index := get_parent().get_child_count() - 1
	get_parent().move_child(frame, taskbar_index)

	_windows[id] = {
		"scene_path": scene_path,
		"params": params,
		"node": app_node,
		"frame": frame,
		"title": title,
	}

	print("[WindowManager] Opened: %s '%s'" % [id, title])
	focus_window(id)
	window_opened.emit(id, params)
	return id


func close_window(id: String) -> void:
	if not _windows.has(id):
		return
	var entry: Dictionary = _windows[id]
	if entry.frame and is_instance_valid(entry.frame):
		entry.frame.queue_free()
	_windows.erase(id)
	if _focused_id == id:
		_focused_id = ""
	print("[WindowManager] Closed: %s" % id)
	window_closed.emit(id)


func focus_window(id: String) -> void:
	if not _windows.has(id):
		return
	# Dim previously focused window
	if _focused_id != "" and _windows.has(_focused_id):
		var prev: Dictionary = _windows[_focused_id]
		if prev.frame and is_instance_valid(prev.frame):
			_set_frame_style(prev.frame, false)

	# Bring to front
	var entry: Dictionary = _windows[id]
	if entry.frame and is_instance_valid(entry.frame):
		_set_frame_style(entry.frame, true)
		var parent := entry.frame.get_parent()
		if parent:
			# Move just before Taskbar (last persistent node)
			var taskbar_index := parent.get_child_count() - 1
			parent.move_child(entry.frame, taskbar_index - 1)

	_focused_id = id
	window_focused.emit(id)


func _set_frame_style(frame: Control, focused: bool) -> void:
	var style := StyleBoxFlat.new()
	if focused:
		style.bg_color = Color(0.14, 0.14, 0.18)
		style.border_color = Color(0.4, 0.6, 1.0)
	else:
		style.bg_color = Color(0.12, 0.12, 0.15)
		style.border_color = Color(0.25, 0.25, 0.3)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	frame.add_theme_stylebox_override("panel", style)


func get_window(id: String) -> Dictionary:
	return _windows.get(id, {})


func get_all_windows() -> Dictionary:
	return _windows.duplicate()


func get_focused() -> String:
	return _focused_id
