extends PanelContainer
## GodotOS image display — uses FileDialog instead of EditorFileDialog

var _image_bytes: PackedByteArray

@onready var _source_label: Label = $VBox/Header/SourceLabel
@onready var _save_btn: Button = $VBox/Header/SaveBtn
@onready var _texture_rect: TextureRect = $VBox/TextureRect


func _ready() -> void:
	_save_btn.pressed.connect(_on_save_pressed)


func setup(base64_data: String, media_type: String, source_name: String) -> void:
	_source_label.text = source_name

	_image_bytes = Marshalls.base64_to_raw(base64_data)
	if _image_bytes.is_empty():
		_source_label.text = source_name + " (decode failed)"
		return

	var image := Image.new()
	var err := OK

	var is_jpg := _image_bytes.size() >= 3 and _image_bytes[0] == 0xFF and _image_bytes[1] == 0xD8 and _image_bytes[2] == 0xFF
	var is_png := _image_bytes.size() >= 4 and _image_bytes[0] == 0x89 and _image_bytes[1] == 0x50
	var is_webp := _image_bytes.size() >= 12 and \
		_image_bytes[8] == 0x57 and _image_bytes[9] == 0x45 and \
		_image_bytes[10] == 0x42 and _image_bytes[11] == 0x50

	if is_jpg:
		err = image.load_jpg_from_buffer(_image_bytes)
	elif is_png:
		err = image.load_png_from_buffer(_image_bytes)
	elif is_webp:
		err = image.load_webp_from_buffer(_image_bytes)
	else:
		err = image.load_png_from_buffer(_image_bytes)
		if err != OK:
			err = image.load_jpg_from_buffer(_image_bytes)
		if err != OK:
			err = image.load_webp_from_buffer(_image_bytes)

	if err != OK:
		_source_label.text = source_name + " (load failed: %d)" % err
		return

	var texture := ImageTexture.create_from_image(image)
	_texture_rect.texture = texture

	var aspect := float(image.get_width()) / float(image.get_height())
	var display_h := mini(image.get_height(), 300)
	var display_w := int(display_h * aspect)
	_texture_rect.custom_minimum_size = Vector2(display_w, display_h)


func _on_save_pressed() -> void:
	if _image_bytes.is_empty():
		return

	var dialog := FileDialog.new()
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	dialog.add_filter("*.png", "PNG Image")
	dialog.add_filter("*.jpg", "JPEG Image")
	dialog.current_file = "image_%d.png" % Time.get_ticks_msec()
	dialog.file_selected.connect(_on_file_selected.bind(dialog))
	add_child(dialog)
	dialog.popup_centered(Vector2i(600, 400))


func _on_file_selected(path: String, dialog: FileDialog) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_buffer(_image_bytes)
		file.close()
	dialog.queue_free()
