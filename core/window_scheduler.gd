extends Node
## WindowScheduler — per-window FPS/priority and visibility throttling
## Background windows get reduced processing. Focused windows get full priority.

var _wm: Node
var _check_interval: float = 2.0
var _timer: Timer

# Per-window scheduling config
var _fps_background: int = 5      # FPS target for background windows
var _fps_focused: int = 60        # FPS target for focused window
var _fps_minimized: int = 1       # FPS target for minimized windows


func _ready() -> void:
	# Connect to WindowManager
	await get_tree().process_frame
	_connect_wm()

	_timer = Timer.new()
	_timer.wait_time = _check_interval
	_timer.autostart = true
	_timer.timeout.connect(_update_priorities)
	add_child(_timer)


func _connect_wm() -> void:
	_wm = Engine.get_singleton("WindowManager") if Engine.has_singleton("WindowManager") else null
	if _wm:
		_wm.window_focused.connect(_on_window_focused)
		_wm.window_closed.connect(_on_window_closed)


func _on_window_focused(win_id: String) -> void:
	_update_priorities()


func _on_window_closed(_win_id: String) -> void:
	_update_priorities()


func _update_priorities() -> void:
	if not _wm:
		return

	var focused_id: String = _wm.get_focused()
	var windows = _wm.get_all_windows()

	for win_id in windows:
		var entry: Dictionary = _wm.get_window_by_id(win_id)
		var frame: Control = entry.get("frame")
		if not frame or not is_instance_valid(frame):
			continue

		var win_state: String = entry.get("window_state", "normal")

		if win_id == focused_id:
			# Focused window — full priority
			frame.visible = true
			frame.process_mode = Node.PROCESS_MODE_INHERIT
		elif win_state == "minimized":
			# Minimized — hidden, minimal processing
			frame.visible = false
			frame.process_mode = Node.PROCESS_MODE_DISABLED
		else:
			# Background window — visible but reduced priority
			frame.visible = true
			frame.process_mode = Node.PROCESS_MODE_WHEN_PAUSED


## Set FPS target for background windows.
func set_background_fps(fps: int) -> void:
	_fps_background = fps


## Set FPS target for the focused window.
func set_focused_fps(fps: int) -> void:
	_fps_focused = fps


## Get current scheduling config.
func get_config() -> Dictionary:
	return {
		"fps_background": _fps_background,
		"fps_focused": _fps_focused,
		"fps_minimized": _fps_minimized,
	}
