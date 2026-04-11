extends Control
## LauncherOverlay — app launcher grid (Super+Space)
## Full-screen overlay with app grid from AppLauncher.

const ACCENT := Color(0.4, 0.6, 1.0)
const BG_COLOR := Color(0.04, 0.04, 0.06, 0.92)
const CARD_BG := Color(0.12, 0.12, 0.18)
const CARD_HOVER := Color(0.18, 0.18, 0.26)
const TEXT_COLOR := Color(0.78, 0.82, 0.92)

var _launcher: Node
var _grid: GridContainer
var _search: LineEdit
var _visible: bool = false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()


func _build_ui() -> void:
	# Semi-transparent background
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = BG_COLOR
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	bg.gui_input.connect(_on_bg_input)
	add_child(bg)

	# Center container
	var center := VBoxContainer.new()
	center.set_anchors_preset(Control.PRESET_CENTER)
	center.offset_left = -300
	center.offset_top = -200
	center.offset_right = 300
	center.offset_bottom = 200
	center.add_theme_constant_override("separation", 20)
	add_child(center)

	# Title
	var title := Label.new()
	title.text = "GodotOS Launcher"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", ACCENT)
	title.add_theme_font_size_override("font_size", 28)
	center.add_child(title)

	# Search bar
	_search = LineEdit.new()
	_search.placeholder_text = "Search apps..."
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.add_theme_font_size_override("font_size", 16)
	var search_style := StyleBoxFlat.new()
	search_style.bg_color = Color(0.08, 0.08, 0.12)
	search_style.set_corner_radius_all(8)
	search_style.content_margin_left = 12
	search_style.content_margin_top = 8
	search_style.content_margin_bottom = 8
	_search.add_theme_stylebox_override("normal", search_style)
	_search.text_changed.connect(_on_search_changed)
	center.add_child(_search)

	# App grid
	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 12)
	_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	center.add_child(_grid)

	# Footer
	var footer := Label.new()
	footer.text = "ESC to close  |  Click to launch"
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.add_theme_color_override("font_color", Color(0.4, 0.4, 0.5))
	footer.add_theme_font_size_override("font_size", 12)
	center.add_child(footer)


func show_launcher() -> void:
	_launcher = Engine.get_singleton("AppLauncher") if Engine.has_singleton("AppLauncher") else null
	visible = true
	_visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_search.text = ""
	_populate_grid()
	_search.grab_focus()


func hide_launcher() -> void:
	visible = false
	_visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func is_launcher_visible() -> bool:
	return _visible


func _populate_grid(filter: String = "") -> void:
	# Clear existing children
	for child in _grid.get_children():
		child.queue_free()

	if not _launcher:
		var label := Label.new()
		label.text = "AppLauncher not available"
		label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		_grid.add_child(label)
		return

	var apps: Array = _launcher.list_apps()
	for app in apps:
		var app_name: String = app.get("name", "")
		var app_id: String = app.get("id", "")

		# Apply filter
		if filter != "" and filter.to_lower() not in app_name.to_lower() and filter.to_lower() not in app_id.to_lower():
			continue

		var card := Button.new()
		card.text = app_name
		if app.get("running", false):
			card.text += " *"
		card.custom_minimum_size = Vector2(130, 80)
		card.flat = true

		var card_style := StyleBoxFlat.new()
		card_style.bg_color = CARD_BG
		card_style.set_corner_radius_all(8)
		card_style.content_margin_left = 8
		card_style.content_margin_right = 8
		card.add_theme_stylebox_override("normal", card_style)

		var card_hover := StyleBoxFlat.new()
		card_hover.bg_color = CARD_HOVER
		card_hover.set_corner_radius_all(8)
		card_hover.content_margin_left = 8
		card_hover.content_margin_right = 8
		card.add_theme_stylebox_override("hover", card_hover)

		card.add_theme_color_override("font_color", TEXT_COLOR)
		card.add_theme_color_override("font_hover_color", Color.WHITE)
		card.add_theme_font_size_override("font_size", 15)

		var captured_id := app_id
		card.pressed.connect(func(): _launch_app(captured_id))

		_grid.add_child(card)


func _launch_app(app_id: String) -> void:
	hide_launcher()
	if _launcher:
		_launcher.launch(app_id)


func _on_search_changed(text: String) -> void:
	_populate_grid(text.strip_edges())


func _on_bg_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		hide_launcher()


func _input(event: InputEvent) -> void:
	if not _visible:
		return
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			hide_launcher()
			get_viewport().set_input_as_handled()
