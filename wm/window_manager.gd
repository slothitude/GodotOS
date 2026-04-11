extends Node
## Window Manager — floating window management for GodotOS
## Instantiates scenes, wraps in window chrome (title bar + controls)
## Supports minimize, maximize, restore, and app_id tracking.

var _windows: Dictionary = {}  # id -> {scene_path, params, node, frame, title, window_state, app_id}
var _next_id: int = 0
var _focused_id: String = ""

signal window_opened(id: String, params: Dictionary)
signal window_closed(id: String)
signal window_focused(id: String)
signal window_minimized(id: String)
signal window_maximized(id: String)
signal window_restored(id: String)

# Title bar button colors
const CLOSE_COLOR := Color(0.8, 0.4, 0.4)
const MINIMIZE_COLOR := Color(0.8, 0.7, 0.3)
const MAXIMIZE_COLOR := Color(0.3, 0.7, 0.5)


func _ready() -> void:
	if not Engine.has_singleton("WindowManager"):
		Engine.register_singleton("WindowManager", self)


func open_app(scene_path: String, params: Dictionary = {}) -> String:
	_next_id += 1
	var id := "win_%03d" % _next_id
	var title: String = params.get("title", "Untitled")
	var app_id: String = params.get("app_id", "")
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
	_set_frame_style(frame, false)

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

	# Minimize button
	var min_btn := Button.new()
	min_btn.text = "_"
	min_btn.custom_minimum_size = Vector2(28, 24)
	min_btn.flat = true
	min_btn.add_theme_color_override("font_color", MINIMIZE_COLOR)
	min_btn.pressed.connect(func(): minimize_window(id))
	title_bar.add_child(min_btn)

	# Maximize button
	var max_btn := Button.new()
	max_btn.text = "□"
	max_btn.custom_minimum_size = Vector2(28, 24)
	max_btn.flat = true
	max_btn.add_theme_color_override("font_color", MAXIMIZE_COLOR)
	max_btn.pressed.connect(func(): maximize_window(id))
	title_bar.add_child(max_btn)

	# Close button
	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.custom_minimum_size = Vector2(28, 24)
	close_btn.flat = true
	close_btn.add_theme_color_override("font_color", CLOSE_COLOR)
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
	# Move frame after all existing children (but before Taskbar/LauncherOverlay)
	var last_index := get_parent().get_child_count() - 1
	get_parent().move_child(frame, last_index)

	# Store pre-maximize geometry for restore
	_windows[id] = {
		"scene_path": scene_path,
		"params": params,
		"node": app_node,
		"frame": frame,
		"title": title,
		"app_id": app_id,
		"window_state": "normal",  # normal | minimized | maximized
		"pre_maximize_position": position,
		"pre_maximize_size": size,
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
		# Focus the next available window
		var remaining := _windows.keys()
		if not remaining.is_empty():
			focus_window(remaining[-1])
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

	# If window is minimized, restore it first
	var entry: Dictionary = _windows[id]
	if entry.get("window_state") == "minimized":
		restore_window(id)

	# Bring to front
	if entry.frame and is_instance_valid(entry.frame):
		_set_frame_style(entry.frame, true)
		entry.frame.visible = true
		var parent = entry.frame.get_parent()
		if parent:
			# Move just before Taskbar/LauncherOverlay (last persistent nodes)
			var last_index = parent.get_child_count() - 1
			parent.move_child(entry.frame, last_index - 1)

	_focused_id = id
	window_focused.emit(id)


func minimize_window(id: String) -> void:
	if not _windows.has(id):
		return
	var entry: Dictionary = _windows[id]
	if entry.get("window_state") == "minimized":
		return

	entry["window_state"] = "minimized"
	if entry.frame and is_instance_valid(entry.frame):
		entry.frame.visible = false

	# Focus next window
	if _focused_id == id:
		_focused_id = ""
		var remaining := []
		for wid in _windows:
			if wid != id and _windows[wid].get("window_state") != "minimized":
				remaining.append(wid)
		if not remaining.is_empty():
			focus_window(remaining[-1])

	print("[WindowManager] Minimized: %s" % id)
	window_minimized.emit(id)


func maximize_window(id: String) -> void:
	if not _windows.has(id):
		return
	var entry: Dictionary = _windows[id]
	if entry.get("window_state") == "maximized":
		return

	# Save current geometry
	if entry.frame and is_instance_valid(entry.frame):
		entry["pre_maximize_position"] = entry.frame.position
		entry["pre_maximize_size"] = entry.frame.size

		# Maximize to fill screen (except taskbar height)
		var screen_size := get_viewport_rect().size
		entry.frame.position = Vector2.ZERO
		entry.frame.size = Vector2(screen_size.x, screen_size.y - 48)

	entry["window_state"] = "maximized"
	print("[WindowManager] Maximized: %s" % id)
	window_maximized.emit(id)


func restore_window(id: String) -> void:
	if not _windows.has(id):
		return
	var entry: Dictionary = _windows[id]
	var current_state: String = entry.get("window_state", "normal")
	if current_state == "normal":
		return

	if entry.frame and is_instance_valid(entry.frame):
		var prev_pos: Vector2 = entry.get("pre_maximize_position", Vector2(100, 100))
		var prev_size: Vector2 = entry.get("pre_maximize_size", Vector2(600, 500))
		entry.frame.position = prev_pos
		entry.frame.size = prev_size
		entry.frame.visible = true

	entry["window_state"] = "normal"
	print("[WindowManager] Restored: %s" % id)
	window_restored.emit(id)


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


func get_window_by_id(id: String) -> Dictionary:
	return _windows.get(id, {})


func get_all_windows() -> Dictionary:
	return _windows.duplicate()


func get_focused() -> String:
	return _focused_id


func get_window_by_app_id(app_id: String) -> String:
	for win_id in _windows:
		if _windows[win_id].get("app_id") == app_id:
			return win_id
	return ""
