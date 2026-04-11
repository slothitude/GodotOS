extends VBoxContainer
## Task Manager — process list + system stats via bridge

var _bridge: Node
var _refresh_timer: Timer

# UI refs
var _stats_label: RichTextLabel
var _process_list: ItemList
var _refresh_btn: Button
var _kill_btn: Button
var _selected_pid: int = -1


func _ready() -> void:
	_bridge = Engine.get_singleton("BridgeClient") if Engine.has_singleton("BridgeClient") else null
	_build_ui()
	_refresh()
	_start_auto_refresh()


func _build_ui() -> void:
	# System stats panel
	_stats_label = RichTextLabel.new()
	_stats_label.bbcode_enabled = true
	_stats_label.custom_minimum_size = Vector2(0, 80)
	_stats_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stats_label.add_theme_font_size_override("normal_font_size", 13)
	var stats_style := StyleBoxFlat.new()
	stats_style.bg_color = Color(0.06, 0.06, 0.10)
	stats_style.content_margin_left = 8
	stats_style.content_margin_right = 8
	stats_style.content_margin_top = 6
	_stats_label.add_theme_stylebox_override("normal", stats_style)
	add_child(_stats_label)

	# Separator
	add_child(HSeparator.new())

	# Process list header
	var header := HBoxContainer.new()
	add_child(header)

	var list_label := Label.new()
	list_label.text = "Processes"
	list_label.add_theme_color_override("font_color", Color(0.78, 0.82, 0.92))
	list_label.add_theme_font_size_override("font_size", 14)
	list_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(list_label)

	_refresh_btn = Button.new()
	_refresh_btn.text = "Refresh"
	_refresh_btn.flat = true
	_refresh_btn.add_theme_color_override("font_color", Color(0.4, 0.6, 1.0))
	_refresh_btn.pressed.connect(_refresh)
	header.add_child(_refresh_btn)

	_kill_btn = Button.new()
	_kill_btn.text = "Kill"
	_kill_btn.flat = true
	_kill_btn.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
	_kill_btn.disabled = true
	_kill_btn.pressed.connect(_kill_selected)
	header.add_child(_kill_btn)

	# Process list
	_process_list = ItemList.new()
	_process_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_process_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_process_list.item_selected.connect(_on_process_selected)
	var list_style := StyleBoxFlat.new()
	list_style.bg_color = Color(0.06, 0.06, 0.10)
	_process_list.add_theme_stylebox_override("panel", list_style)
	add_child(_process_list)


func _start_auto_refresh() -> void:
	_refresh_timer = Timer.new()
	_refresh_timer.wait_time = 5.0
	_refresh_timer.autostart = true
	_refresh_timer.timeout.connect(_refresh)
	add_child(_refresh_timer)


func _refresh() -> void:
	if not _bridge or not _bridge.is_bridge_connected():
		_stats_label.text = "[color=#ff4444]Bridge not connected[/color]"
		return

	# Get system info
	var sys_result = await _bridge.call_service("system", "info", {})
	if not sys_result.has("error"):
		var info_text := ""
		if sys_result.has("memory_used_mb"):
			info_text += "[color=#4488ff]Memory:[/color] %d / %d MB (%.1f%%)\n" % [
				sys_result.memory_used_mb, sys_result.memory_total_mb, sys_result.memory_used_pct]
		if sys_result.has("disk_used_gb"):
			info_text += "[color=#4488ff]Disk:[/color] %.1f / %.1f GB (%.1f%%)\n" % [
				sys_result.disk_used_gb, sys_result.disk_total_gb, sys_result.disk_used_pct]
		if sys_result.has("uptime_hours"):
			info_text += "[color=#4488ff]Uptime:[/color] %.1f hours" % sys_result.uptime_hours
		_stats_label.text = info_text

	# Get process list
	_process_list.clear()
	var proc_result = await _bridge.call_service("process", "list", {})
	if proc_result.has("error"):
		_process_list.add_item("Error: %s" % proc_result.error)
		return

	var procs: Array = proc_result.get("processes", [])
	for proc in procs:
		var pid: int = proc.get("pid", 0)
		var cmd: String = proc.get("cmdline", "?")
		var state: String = proc.get("state", "?")
		var line := "PID %6d  [%s]  %s" % [pid, state, cmd]
		_process_list.add_item(line)
		_process_list.set_item_metadata(_process_list.get_item_count() - 1, proc)


func _on_process_selected(index: int) -> void:
	var meta = _process_list.get_item_metadata(index)
	if meta is Dictionary:
		_selected_pid = meta.get("pid", -1)
		_kill_btn.disabled = false


func _kill_selected() -> void:
	if _selected_pid < 0 or not _bridge:
		return
	var result = await _bridge.call_service("process", "kill", {"pid": _selected_pid})
	if result.has("error"):
		print("[TaskManager] Kill failed: %s" % result.error)
	_selected_pid = -1
	_kill_btn.disabled = true
	# Refresh after kill
	await get_tree().create_timer(0.5).timeout
	_refresh()
