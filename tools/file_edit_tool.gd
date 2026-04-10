class_name GCFileEditTool
extends GCBaseTool
## String replacement edits in existing files


func _init() -> void:
	super._init(
		"Edit",
		"Performs exact string replacements in files. The edit will FAIL if old_string is not unique in the file.",
		{
			"file_path": {
				"type": "string",
				"description": "The absolute path to the file to modify"
			},
			"old_string": {
				"type": "string",
				"description": "The text to replace"
			},
			"new_string": {
				"type": "string",
				"description": "The text to replace it with"
			},
			"replace_all": {
				"type": "boolean",
				"description": "Replace all occurrences of old_string (default false)"
			}
		}
	)
	is_read_only = false


func validate_input(input: Dictionary) -> Dictionary:
	if not input.has("file_path"):
		return {"valid": false, "error": "file_path is required"}
	if not input.has("old_string"):
		return {"valid": false, "error": "old_string is required"}
	if not input.has("new_string"):
		return {"valid": false, "error": "new_string is required"}
	return {"valid": true}


func execute(input: Dictionary, context: Dictionary) -> Dictionary:
	var file_path: String = input.get("file_path", "")
	var old_string: String = input.get("old_string", "")
	var new_string: String = input.get("new_string", "")
	var replace_all: bool = input.get("replace_all", false)

	if file_path == "":
		return {"success": false, "error": "file_path is required"}
	if old_string == "":
		return {"success": false, "error": "old_string cannot be empty"}

	# Resolve res:// paths
	if file_path.begins_with("res://"):
		file_path = ProjectSettings.globalize_path(file_path)

	if not FileAccess.file_exists(file_path):
		return {"success": false, "error": "File not found: %s" % file_path}

	var file := FileAccess.open(file_path, FileAccess.READ)
	if not file:
		return {"success": false, "error": "Cannot open file: %s" % file_path}

	var content := file.get_as_text()
	file.close()

	# Check uniqueness unless replace_all
	if not replace_all:
		var count := content.count(old_string)
		if count == 0:
			return {"success": false, "error": "old_string not found in file"}
		if count > 1:
			return {"success": false, "error": "old_string is not unique (%d occurrences). Provide more context or use replace_all." % count}

	if old_string == new_string:
		return {"success": false, "error": "old_string and new_string are identical"}

	# Perform replacement
	var new_content: String
	if replace_all:
		new_content = content.replace(old_string, new_string)
	else:
		var idx := content.find(old_string)
		new_content = content.substr(0, idx) + new_string + content.substr(idx + old_string.length())

	# Write back
	var write_file := FileAccess.open(file_path, FileAccess.WRITE)
	if not write_file:
		return {"success": false, "error": "Cannot write file: %s" % file_path}

	write_file.store_string(new_content)
	write_file.close()

	var replacement_count := 1 if not replace_all else content.count(old_string)
	return {"success": true, "data": "Replaced %d occurrence(s) in %s" % [replacement_count, file_path]}
