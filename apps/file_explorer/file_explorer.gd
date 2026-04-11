extends VBoxContainer
## File Explorer — tree+list browser via VirtualFS and bridge fs service

var _vfs: Node
var _bridge: Node
var _current_path: String = "/home/user"

# UI refs
var _path_bar: LineEdit
var _file_list: ItemList
var _info_label: Label


func _ready() -> void:
	_vfs = Engine.get_singleton("VirtualFS") if Engine.has_singleton("VirtualFS") else null
	_bridge = Engine.get_singleton("BridgeClient") if Engine.has_singleton("BridgeClient") else null
	_build_ui()
	_navigate_to(_current_path)


func _build_ui() -> void:
	# Path bar
	var path_row := HBoxContainer.new()
	add_child(path_row)

	var path_label := Label.new()
	path_label.text = "Path:"
	path_label.add_theme_color_override("font_color", Color(0.5, 0.52, 0.6))
	path_label.add_theme_font_size_override("font_size", 13)
	path_row.add_child(path_label)

	_path_bar = LineEdit.new()
	_path_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_path_bar.text = _current_path
	_path_bar.add_theme_font_size_override("font_size", 13)
	var input_style := StyleBoxFlat.new()
	input_style.bg_color = Color(0.08, 0.08, 0.12)
	input_style.content_margin_left = 6
	_path_bar.add_theme_stylebox_override("normal", input_style)
	_path_bar.text_submitted.connect(_on_path_submitted)
	path_row.add_child(_path_bar)

	# Separator
	var sep := HSeparator.new()
	add_child(sep)

	# File list
	_file_list = ItemList.new()
	_file_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_file_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_file_list.item_activated.connect(_on_item_activated)
	_file_list.item_clicked.connect(_on_item_clicked)
	var list_style := StyleBoxFlat.new()
	list_style.bg_color = Color(0.06, 0.06, 0.10)
	list_style.content_margin_left = 4
	_file_list.add_theme_stylebox_override("panel", list_style)
	add_child(_file_list)

	# Info bar
	_info_label = Label.new()
	_info_label.text = ""
	_info_label.add_theme_color_override("font_color", Color(0.5, 0.52, 0.6))
	_info_label.add_theme_font_size_override("font_size", 12)
	add_child(_info_label)


func _navigate_to(path: String) -> void:
	_current_path = path
	_path_bar.text = path
	_file_list.clear()

	if not _bridge or not _bridge.is_bridge_connected():
		_file_list.add_item("(Bridge not connected)")
		_info_label.text = "Offline"
		return

	# Resolve virtual path to host path
	var host_path := path
	if _vfs:
		host_path = _vfs.resolve(path)

	var result = await _bridge.call_service("fs", "list_dir", {"path": host_path})
	if result.has("error"):
		_file_list.add_item("Error: %s" % result.error)
		_info_label.text = "Error"
		return

	var entries: Array = result.get("entries", [])
	# Add parent directory
	if path != "/":
		_file_list.add_item("..  (parent)")
		_file_list.set_item_metadata(0, {"name": "..", "type": "parent"})

	for entry in entries:
		var name: String = entry.get("name", "?")
		var type: String = entry.get("type", "file")
		var size: int = entry.get("size", 0)
		var icon_prefix := "[D] " if type == "directory" else "    "
		_file_list.add_item(icon_prefix + name)
		var idx := _file_list.get_item_count() - 1
		_file_list.set_item_metadata(idx, entry)

	_info_label.text = "%d items | %s" % [entries.size(), path]


func _on_path_submitted(path: String) -> void:
	_navigate_to(path)


func _on_item_activated(index: int) -> void:
	var meta = _file_list.get_item_metadata(index)
	if not meta:
		return

	if meta is Dictionary:
		if meta.get("type") == "parent":
			# Go up one level
			var parts := _current_path.split("/")
			if parts.size() > 1:
				parts.remove_at(parts.size() - 1)
				var parent := "/".join(parts)
				if parent == "":
					parent = "/"
				_navigate_to(parent)
		elif meta.get("type") == "directory":
			var name: String = meta.get("name", "")
			var new_path := _current_path
			if not new_path.ends_with("/"):
				new_path += "/"
			new_path += name
			_navigate_to(new_path)
		else:
			# File — open with OS default app
			var name: String = meta.get("name", "")
			var host_path := _current_path
			if _vfs:
				host_path = _vfs.resolve(host_path)
			if not host_path.ends_with("/"):
				host_path += "/"
			host_path += name
			if _bridge and _bridge.is_bridge_connected():
				var result = await _bridge.call_service("process", "open", {"path": host_path})
				if result.has("error"):
					_info_label.text = "Open failed: %s" % result.error
				else:
					_info_label.text = "Opened: %s" % name
			else:
				_info_label.text = "Cannot open — bridge offline"


func _on_item_clicked(index: int, _at: Vector2, _mouse_btn: int) -> void:
	var meta = _file_list.get_item_metadata(index)
	if meta is Dictionary and meta.get("type") != "parent":
		_info_label.text = "%s | %s | %d bytes" % [meta.get("name", ""), meta.get("type", ""), meta.get("size", 0)]
