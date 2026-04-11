extends Control
## Taskbar — "The Nerve Ribbon" for GodotOS
## Three zones: AI Orbit (left), Window Dots (center), System Triage (right)

# Theme colors
const ACCENT := Color(0.4, 0.6, 1.0)
const BG_COLOR := Color(0.08, 0.08, 0.12, 0.85)
const TEXT_COLOR := Color(0.78, 0.82, 0.92)
const DIM_TEXT := Color(0.5, 0.52, 0.6)
const RED := Color(0.9, 0.3, 0.3)
const GREEN := Color(0.3, 0.85, 0.45)
const PILL_BG := Color(0.18, 0.18, 0.24)
const PILL_BG_FOCUSED := Color(0.22, 0.22, 0.30)
const PILL_BORDER := Color(0.35, 0.35, 0.42)
const HEIGHT := 48

var _wm: Node
var _command_bus: Node
var _bridge_client: Node

# Internal state
var _ai_state: String = "idle"  # idle | thinking | error
var _command_count: int = 0
var _bridge_connected: bool = false
var _pills: Dictionary = {}  # window_id -> Button

# UI refs
var _glow_line: ColorRect
var _beacon: ColorRect
var _ai_label: Label
var _pill_container: HBoxContainer
var _bridge_dot: ColorRect
var _cmd_badge: Label
var _clock_label: Label
var _glow_tween: Tween


func setup(wm: Node, command_bus: Node, bridge_client: Node) -> void:
	_wm = wm
	_command_bus = command_bus
	_bridge_client = bridge_client

	# Connect window manager signals
	if _wm:
		_wm.window_opened.connect(_on_window_opened)
		_wm.window_closed.connect(_on_window_closed)
		_wm.window_focused.connect(_on_window_focused)
		# Create pills for any already-open windows
		for win_id in _wm.get_all_windows():
			var entry: Dictionary = _wm.get_window_by_id(win_id)
			_create_pill(win_id, entry.get("title", "Untitled"))

	# Connect command bus signals
	if _command_bus:
		_command_bus.command_started.connect(_on_command_started)
		_command_bus.command_completed.connect(_on_command_finished)
		_command_bus.command_failed.connect(_on_command_failed)

	# Bridge status polling
	var bridge_timer := Timer.new()
	bridge_timer.wait_time = 2.0
	bridge_timer.autostart = true
	bridge_timer.timeout.connect(_poll_bridge_status)
	add_child(bridge_timer)

	# Clock timer
	var clock_timer := Timer.new()
	clock_timer.wait_time = 60.0
	clock_timer.autostart = true
	clock_timer.timeout.connect(_update_clock)
	add_child(clock_timer)

	_update_clock()
	_poll_bridge_status()
	_start_glow_pulse()
	_set_ai_state("idle")


func _ready() -> void:
	anchors_preset = Control.PRESET_BOTTOM_WIDE
	anchor_top = 1.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_top = -HEIGHT
	offset_bottom = 0
	offset_left = 0
	offset_right = 0
	grow_vertical = Control.GROW_DIRECTION_BOTH
	mouse_filter = Control.MOUSE_FILTER_PASS

	# Background panel
	var bg := PanelContainer.new()
	bg.name = "Background"
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = BG_COLOR
	bg_style.set_border_width_all(0)
	bg_style.set_corner_radius_all(0)
	bg.add_theme_stylebox_override("panel", bg_style)
	add_child(bg)

	# Accent glow line (2px, top edge)
	_glow_line = ColorRect.new()
	_glow_line.name = "GlowLine"
	_glow_line.color = ACCENT
	_glow_line.position = Vector2(0, 0)
	_glow_line.size = Vector2(get_viewport_rect().size.x, 2)
	_glow_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_glow_line)

	# Main horizontal layout
	var h_box := HBoxContainer.new()
	h_box.name = "Layout"
	h_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	h_box.offset_top = 4
	h_box.offset_bottom = -4
	h_box.add_theme_constant_override("separation", 8)
	add_child(h_box)

	# ── Zone 1: AI Orbit (left) ──
	var ai_zone := HBoxContainer.new()
	ai_zone.name = "AIOrbit"
	ai_zone.custom_minimum_size = Vector2(200, 0)
	ai_zone.add_theme_constant_override("separation", 10)
	h_box.add_child(ai_zone)

	# Left margin
	var left_pad := Control.new()
	left_pad.custom_minimum_size = Vector2(12, 0)
	ai_zone.add_child(left_pad)

	# Beacon (circular indicator)
	_beacon = ColorRect.new()
	_beacon.name = "Beacon"
	_beacon.custom_minimum_size = Vector2(24, 24)
	_beacon.size = Vector2(24, 24)
	_beacon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var beacon_style := StyleBoxFlat.new()
	beacon_style.bg_color = ACCENT
	beacon_style.set_corner_radius_all(12)
	_beacon.add_theme_stylebox_override("panel", beacon_style)
	ai_zone.add_child(_beacon)

	# AI status label
	_ai_label = Label.new()
	_ai_label.name = "AILabel"
	_ai_label.text = "AI Idle"
	_ai_label.add_theme_color_override("font_color", TEXT_COLOR)
	_ai_label.add_theme_font_size_override("font_size", 14)
	_ai_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ai_zone.add_child(_ai_label)

	# Launcher button (grid icon)
	var launcher_btn := Button.new()
	launcher_btn.name = "LauncherBtn"
	launcher_btn.text = "☯"
	launcher_btn.flat = true
	launcher_btn.add_theme_color_override("font_color", TEXT_COLOR)
	launcher_btn.add_theme_color_override("font_hover_color", Color.WHITE)
	launcher_btn.add_theme_font_size_override("font_size", 18)
	launcher_btn.custom_minimum_size = Vector2(36, 36)
	launcher_btn.tooltip_text = "App Launcher (Super+Space)"
	launcher_btn.pressed.connect(_on_launcher_pressed)
	ai_zone.add_child(launcher_btn)

	# ── Zone 2: Window Dots (center, flex) ──
	_pill_container = HBoxContainer.new()
	_pill_container.name = "WindowDots"
	_pill_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pill_container.add_theme_constant_override("separation", 6)
	_pill_container.alignment = BoxContainer.ALIGNMENT_CENTER
	h_box.add_child(_pill_container)

	# ── Zone 3: System Triage (right) ──
	var sys_zone := HBoxContainer.new()
	sys_zone.name = "SystemTriage"
	sys_zone.custom_minimum_size = Vector2(280, 0)
	sys_zone.add_theme_constant_override("separation", 10)
	h_box.add_child(sys_zone)

	# Bridge dot
	_bridge_dot = ColorRect.new()
	_bridge_dot.name = "BridgeDot"
	_bridge_dot.custom_minimum_size = Vector2(12, 12)
	_bridge_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dot_style := StyleBoxFlat.new()
	dot_style.bg_color = RED
	dot_style.set_corner_radius_all(6)
	_bridge_dot.add_theme_stylebox_override("panel", dot_style)
	# Center-align the dot vertically
	var dot_align := VBoxContainer.new()
	dot_align.add_theme_constant_override("separation", 0)
	dot_align.alignment = BoxContainer.ALIGNMENT_CENTER
	dot_align.add_child(_bridge_dot)
	sys_zone.add_child(dot_align)

	# Bridge label
	var bridge_label := Label.new()
	bridge_label.text = "Bridge"
	bridge_label.add_theme_color_override("font_color", DIM_TEXT)
	bridge_label.add_theme_font_size_override("font_size", 12)
	bridge_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sys_zone.add_child(bridge_label)

	# Command count badge
	_cmd_badge = Label.new()
	_cmd_badge.name = "CmdBadge"
	_cmd_badge.text = "0 cmd"
	_cmd_badge.add_theme_color_override("font_color", DIM_TEXT)
	_cmd_badge.add_theme_font_size_override("font_size", 12)
	_cmd_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sys_zone.add_child(_cmd_badge)

	# Right spacer to push clock right
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sys_zone.add_child(spacer)

	# Clock
	_clock_label = Label.new()
	_clock_label.name = "Clock"
	_clock_label.text = "00:00"
	_clock_label.add_theme_color_override("font_color", TEXT_COLOR)
	_clock_label.add_theme_font_size_override("font_size", 15)
	_clock_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sys_zone.add_child(_clock_label)

	# Right margin
	var right_pad := Control.new()
	right_pad.custom_minimum_size = Vector2(12, 0)
	sys_zone.add_child(right_pad)


# ── Glow Line Pulse ──

func _start_glow_pulse() -> void:
	if _glow_tween and _glow_tween.is_valid():
		_glow_tween.kill()
	_glow_tween = create_tween().set_loops()
	_glow_tween.tween_property(_glow_line, "color:a", 0.8, 1.2).set_trans(Tween.TRANS_SINE)
	_glow_tween.tween_property(_glow_line, "color:a", 0.3, 1.2).set_trans(Tween.TRANS_SINE)


func _stop_glow_pulse() -> void:
	if _glow_tween and _glow_tween.is_valid():
		_glow_tween.kill()
	_glow_line.color.a = 0.5


# ── AI State ──

func _set_ai_state(state: String) -> void:
	_ai_state = state
	var beacon_style := _beacon.get_theme_stylebox("panel") as StyleBoxFlat
	if not beacon_style:
		beacon_style = StyleBoxFlat.new()
		beacon_style.set_corner_radius_all(12)
		_beacon.add_theme_stylebox_override("panel", beacon_style)

	match state:
		"idle":
			beacon_style.bg_color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.5)
			_ai_label.text = "AI Idle"
			_stop_glow_pulse()
		"thinking":
			beacon_style.bg_color = ACCENT
			_ai_label.text = "AI Thinking..."
			_start_glow_pulse()
		"error":
			beacon_style.bg_color = RED
			_ai_label.text = "AI Error"
			_stop_glow_pulse()


# ── Window Pills ──

func _create_pill(win_id: String, title: String) -> void:
	if _pills.has(win_id):
		return

	var pill := Button.new()
	pill.name = "Pill_%s" % win_id
	pill.text = title
	pill.custom_minimum_size = Vector2(130, 32)
	pill.flat = true

	var pill_style := StyleBoxFlat.new()
	pill_style.bg_color = PILL_BG
	pill_style.border_color = PILL_BORDER
	pill_style.set_border_width_all(1)
	pill_style.set_corner_radius_all(12)
	pill_style.content_margin_left = 12
	pill_style.content_margin_right = 12
	pill.add_theme_stylebox_override("normal", pill_style)

	var pill_hover := StyleBoxFlat.new()
	pill_hover.bg_color = PILL_BG_FOCUSED
	pill_hover.border_color = PILL_BORDER
	pill_hover.set_border_width_all(1)
	pill_hover.set_corner_radius_all(12)
	pill_hover.content_margin_left = 12
	pill_hover.content_margin_right = 12
	pill.add_theme_stylebox_override("hover", pill_hover)

	pill.add_theme_color_override("font_color", DIM_TEXT)
	pill.add_theme_color_override("font_hover_color", TEXT_COLOR)
	pill.add_theme_font_size_override("font_size", 13)

	pill.pressed.connect(func(): _on_pill_pressed(win_id))

	# Animate in
	pill.modulate.a = 0.0
	_pill_container.add_child(pill)
	var tw := create_tween()
	tw.tween_property(pill, "modulate:a", 1.0, 0.2)

	_pills[win_id] = pill

	# Highlight if focused
	if _wm and _wm.get_focused() == win_id:
		_style_pill_focused(pill, true)


func _remove_pill(win_id: String) -> void:
	if not _pills.has(win_id):
		return
	var pill: Button = _pills[win_id]
	_pills.erase(win_id)
	# Animate out
	var tw := create_tween()
	tw.tween_property(pill, "modulate:a", 0.0, 0.15)
	tw.tween_callback(pill.queue_free)


func _style_pill_focused(pill: Button, focused: bool) -> void:
	var style_key := "normal" if focused else "normal"
	var pill_style := pill.get_theme_stylebox(style_key) as StyleBoxFlat
	if pill_style:
		if focused:
			pill_style.bg_color = PILL_BG_FOCUSED
			pill_style.border_color = ACCENT
			pill.add_theme_color_override("font_color", TEXT_COLOR)
		else:
			pill_style.bg_color = PILL_BG
			pill_style.border_color = PILL_BORDER
			pill.add_theme_color_override("font_color", DIM_TEXT)


func _on_pill_pressed(win_id: String) -> void:
	if _wm:
		_wm.focus_window(win_id)


# ── Signal Handlers ──

func _on_window_opened(win_id: String, _params: Dictionary) -> void:
	if _wm:
		var entry: Dictionary = _wm.get_window_by_id(win_id)
		_create_pill(win_id, entry.get("title", "Untitled"))


func _on_window_closed(win_id: String) -> void:
	_remove_pill(win_id)


func _on_window_focused(win_id: String) -> void:
	# Dim all pills, highlight the focused one
	for id in _pills:
		if _pills[id] and is_instance_valid(_pills[id]):
			_style_pill_focused(_pills[id], id == win_id)


func _on_command_started(_id: String, _command: Dictionary) -> void:
	_command_count += 1
	_update_cmd_badge()
	_set_ai_state("thinking")


func _on_command_finished(_id: String, _result: Dictionary) -> void:
	_update_cmd_badge()
	if _command_bus and _command_bus.get_pending().is_empty():
		_set_ai_state("idle")


func _on_command_failed(_id: String, _error: String) -> void:
	_update_cmd_badge()
	if _command_bus and _command_bus.get_pending().is_empty():
		_set_ai_state("error")
		# Revert to idle after a few seconds
		get_tree().create_timer(3.0).timeout.connect(func(): _set_ai_state("idle"))


func _update_cmd_badge() -> void:
	_cmd_badge.text = "%d cmd" % _command_count


# ── Polling ──

func _poll_bridge_status() -> void:
	if _bridge_client and _bridge_client.has_method("is_bridge_connected"):
		_bridge_connected = _bridge_client.is_bridge_connected()
	else:
		_bridge_connected = false

	var dot_style := _bridge_dot.get_theme_stylebox("panel") as StyleBoxFlat
	if not dot_style:
		dot_style = StyleBoxFlat.new()
		dot_style.set_corner_radius_all(6)
		_bridge_dot.add_theme_stylebox_override("panel", dot_style)
	dot_style.bg_color = GREEN if _bridge_connected else RED


func _update_clock() -> void:
	var time_dict := Time.get_time_dict_from_system()
	_clock_label.text = "%02d:%02d" % [time_dict.hour, time_dict.minute]


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		if _glow_line:
			_glow_line.size.x = size.x


func _on_launcher_pressed() -> void:
	var shell = get_tree().root.get_node_or_null("Shell")
	if shell and shell.launcher_overlay:
		if shell.launcher_overlay.is_launcher_visible():
			shell.launcher_overlay.hide_launcher()
		else:
			shell.launcher_overlay.show_launcher()
