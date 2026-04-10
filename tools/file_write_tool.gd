class_name GCFileWriteTool
extends GCBaseTool
## Create or overwrite files


func _init() -> void:
	super._init(
		"Write",
		"Writes a file to the local filesystem. Will overwrite existing files.",
		{
			"file_path": {
				"type": "string",
				"description": "The absolute path to write to"
			},
			"content": {
				"type": "string",
				"description": "The content to write"
			}
		}
	)
	is_read_only = false


func validate_input(input: Dictionary) -> Dictionary:
	if not input.has("file_path"):
		return {"valid": false, "error": "file_path is required"}
	if not input.has("content"):
		return {"valid": false, "error": "content is required"}
	return {"valid": true}


func execute(input: Dictionary, context: Dictionary) -> Dictionary:
	var file_path: String = input.get("file_path", "")
	var content: String = input.get("content", "")

	if file_path == "":
		return {"success": false, "error": "file_path is required"}

	# Resolve res:// paths
	if file_path.begins_with("res://"):
		file_path = ProjectSettings.globalize_path(file_path)

	# Ensure parent directory exists
	var dir := file_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		var err := DirAccess.make_dir_recursive_absolute(dir)
		if err != OK:
			return {"success": false, "error": "Cannot create directory: %s (error %d)" % [dir, err]}

	var file := FileAccess.open(file_path, FileAccess.WRITE)
	if not file:
		return {"success": false, "error": "Cannot open file for writing: %s" % file_path}

	file.store_string(content)
	file.close()

	return {"success": true, "data": "File written successfully: %s (%d bytes)" % [file_path, content.length()]}
