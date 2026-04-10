class_name GCFileReadTool
extends GCBaseTool
## Read file contents — text files with optional offset/limit, images as base64


func _init() -> void:
	super._init(
		"Read",
		"Reads a file from the local filesystem. You can access any file directly by using this tool.",
		{
			"file_path": {
				"type": "string",
				"description": "The absolute path to the file to read"
			},
			"offset": {
				"type": "integer",
				"description": "Line number to start reading from (1-based)"
			},
			"limit": {
				"type": "integer",
				"description": "Number of lines to read"
			}
		}
	)


func validate_input(input: Dictionary) -> Dictionary:
	if not input.has("file_path"):
		return {"valid": false, "error": "file_path is required"}
	return {"valid": true}


func execute(input: Dictionary, context: Dictionary) -> Dictionary:
	var file_path: String = input.get("file_path", "")

	if file_path == "":
		return {"success": false, "error": "file_path is required"}

	# Resolve res:// paths
	if file_path.begins_with("res://"):
		file_path = ProjectSettings.globalize_path(file_path)

	if not FileAccess.file_exists(file_path):
		return {"success": false, "error": "File not found: %s" % file_path}

	# Check if it's a binary/image file
	var ext := file_path.get_extension().to_lower()
	var image_extensions := ["png", "jpg", "jpeg", "gif", "bmp", "webp", "svg"]
	if ext in image_extensions:
		return _read_image(file_path)

	# Read as text
	var file := FileAccess.open(file_path, FileAccess.READ)
	if not file:
		return {"success": false, "error": "Cannot open file: %s" % file_path}

	var text := file.get_as_text()
	file.close()

	# Apply offset/limit
	var offset: int = input.get("offset", 0)
	var limit: int = input.get("limit", 0)

	if offset > 0 or limit > 0:
		var lines := text.split("\n")
		if offset > 0:
			offset = maxi(offset - 1, 0)  # Convert to 0-based
			lines = lines.slice(offset)
		if limit > 0:
			lines = lines.slice(0, limit)
		text = "\n".join(lines)

	return {"success": true, "data": text}


func _read_image(file_path: String) -> Dictionary:
	var image := Image.new()
	var err: int
	var ext := file_path.get_extension().to_lower()

	match ext:
		"png":
			err = image.load_png_from_buffer(FileAccess.get_file_as_bytes(file_path))
		"jpg", "jpeg":
			err = image.load_jpg_from_buffer(FileAccess.get_file_as_bytes(file_path))
		"webp":
			err = image.load_webp_from_buffer(FileAccess.get_file_as_bytes(file_path))
		_:
			return {"success": false, "error": "Unsupported image format: %s" % ext}

	if err != OK:
		return {"success": false, "error": "Failed to load image: %s" % file_path}

	return {"success": true, "data": "[Image: %s %dx%d]" % [file_path, image.get_width(), image.get_height()]}
