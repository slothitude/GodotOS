extends VBoxContainer
## System Settings — GodotOS configuration panel

var _settings: RefCounted  # GCSettings

# UI refs
var _provider_option: OptionButton
var _model_input: LineEdit
var _base_url_input: LineEdit
var _api_key_input: LineEdit
var _temp_slider: HSlider
var _temp_label: Label
var _theme_option: OptionButton
var _save_btn: Button


func _ready() -> void:
	if Engine.has_singleton("CommandBus"):
		var cb = Engine.get_singleton("CommandBus")
		# Access settings through the shell — we'll get it from the tree
		var shell = get_tree().root.get_node_or_null("Shell")
		if shell:
			_settings = shell.gc_settings
	_build_ui()
	_load_settings()


func _build_ui() -> void:
	# Header
	var header := Label.new()
	header.text = "  System Settings"
	header.add_theme_color_override("font_color", Color(0.4, 0.6, 1.0))
	header.add_theme_font_size_override("font_size", 18)
	header.custom_minimum_size = Vector2(0, 36)
	add_child(header)

	add_child(HSeparator.new())

	# Scroll container for settings
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(scroll)

	var container := VBoxContainer.new()
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.add_theme_constant_override("separation", 12)
	scroll.add_child(container)

	# Provider
	container.add_child(_make_label("Provider:"))
	_provider_option = OptionButton.new()
	_provider_option.add_item("anthropic", 0)
	_provider_option.add_item("openai", 1)
	_provider_option.add_item("openai_compatible", 2)
	_provider_option.add_item("nvidia", 3)
	container.add_child(_provider_option)

	# Model
	container.add_child(_make_label("Model:"))
	_model_input = _make_line_edit("")
	container.add_child(_model_input)

	# Base URL
	container.add_child(_make_label("Base URL:"))
	_base_url_input = _make_line_edit("")
	container.add_child(_base_url_input)

	# API Key
	container.add_child(_make_label("API Key:"))
	_api_key_input = _make_line_edit("")
	_api_key_input.secret = true
	container.add_child(_api_key_input)

	# Temperature
	container.add_child(_make_label("Temperature:"))
	var temp_row := HBoxContainer.new()
	container.add_child(temp_row)
	_temp_slider = HSlider.new()
	_temp_slider.min_value = 0.0
	_temp_slider.max_value = 2.0
	_temp_slider.step = 0.1
	_temp_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_temp_slider.value_changed.connect(func(v): _temp_label.text = "%.1f" % v)
	temp_row.add_child(_temp_slider)
	_temp_label = Label.new()
	_temp_label.text = "1.0"
	_temp_label.custom_minimum_size = Vector2(40, 0)
	_temp_label.add_theme_color_override("font_color", Color(0.5, 0.52, 0.6))
	temp_row.add_child(_temp_label)

	# Theme
	container.add_child(_make_label("Theme:"))
	_theme_option = OptionButton.new()
	_theme_option.add_item("Dark", 0)
	_theme_option.add_item("Light", 1)
	container.add_child(_theme_option)

	# Save button
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 16)
	container.add_child(spacer)

	_save_btn = Button.new()
	_save_btn.text = "Save Settings"
	_save_btn.custom_minimum_size = Vector2(0, 36)
	var btn_style := StyleBoxFlat.new()
	btn_style.bg_color = Color(0.2, 0.4, 0.8)
	btn_style.set_corner_radius_all(6)
	_save_btn.add_theme_stylebox_override("normal", btn_style)
	_save_btn.add_theme_color_override("font_color", Color.WHITE)
	_save_btn.pressed.connect(_save_settings)
	container.add_child(_save_btn)


func _make_label(text: String) -> Label:
	var label := Label.new()
	label.text = "  " + text
	label.add_theme_color_override("font_color", Color(0.6, 0.62, 0.7))
	label.add_theme_font_size_override("font_size", 13)
	return label


func _make_line_edit(placeholder: String) -> LineEdit:
	var le := LineEdit.new()
	le.placeholder_text = placeholder
	le.add_theme_font_size_override("font_size", 13)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.12)
	style.content_margin_left = 8
	le.add_theme_stylebox_override("normal", style)
	return le


func _load_settings() -> void:
	if not _settings:
		return
	var provider: String = _settings.get_setting("provider", "anthropic")
	var providers := ["anthropic", "openai", "openai_compatible", "nvidia"]
	var idx := providers.find(provider)
	if idx >= 0:
		_provider_option.selected = idx
	_model_input.text = _settings.get_setting("model", "")
	_base_url_input.text = _settings.get_setting("base_url", "")
	_api_key_input.text = _settings.get_setting("api_key", "")
	_temp_slider.value = _settings.get_setting("temperature", 1.0)
	var theme: String = _settings.get_setting("theme", "dark")
	_theme_option.selected = 0 if theme == "dark" else 1


func _save_settings() -> void:
	if not _settings:
		return
	var providers := ["anthropic", "openai", "openai_compatible", "nvidia"]
	_settings.set_setting("provider", providers[_provider_option.selected])
	_settings.set_setting("model", _model_input.text)
	_settings.set_setting("base_url", _base_url_input.text)
	_settings.set_setting("api_key", _api_key_input.text)
	_settings.set_setting("temperature", _temp_slider.value)
	_settings.set_setting("theme", "dark" if _theme_option.selected == 0 else "light")
	_save_btn.text = "Saved!"
	await get_tree().create_timer(1.5).timeout
	_save_btn.text = "Save Settings"
