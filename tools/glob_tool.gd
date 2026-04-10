class_name GCGlobTool
extends GCBaseTool
## File pattern matching using recursive directory traversal


func _init() -> void:
	super._init(
		"Glob",
		"Fast file pattern matching tool. Supports glob patterns like **/*.js or src/**/*.ts.",
		{
			"pattern": {
				"type": "string",
				"description": "The glob pattern to match files against (e.g. **/*.gd)"
			},
			"path": {
				"type": "string",
				"description": "Directory to search in (defaults to project root)"
			}
		}
	)


func validate_input(input: Dictionary) -> Dictionary:
	if not input.has("pattern"):
		return {"valid": false, "error": "pattern is required"}
	return {"valid": true}


func execute(input: Dictionary, context: Dictionary) -> Dictionary:
	var pattern: String = input.get("pattern", "")
	var base_path: String = input.get("path", "")

	if pattern == "":
		return {"success": false, "error": "pattern is required"}

	# Default to project root
	if base_path == "":
		base_path = ProjectSettings.globalize_path("res://")
	elif base_path.begins_with("res://"):
		base_path = ProjectSettings.globalize_path(base_path)

	# Normalize path
	if base_path.right(1) != "/":
		base_path += "/"

	if not DirAccess.dir_exists_absolute(base_path):
		return {"success": false, "error": "Directory not found: %s" % base_path}

	var results: Array = []
	_glob_recursive(base_path, pattern, results)

	# Sort by modification time (newest first)
	results.sort_custom(func(a, b): return a < b)

	if results.size() > 200:
		results = results.slice(0, 200)

	return {"success": true, "data": "\n".join(results)}


func _glob_recursive(dir_path: String, pattern: String, results: Array) -> void:
	var da := DirAccess.open(dir_path)
	if not da:
		return

	# Skip hidden and common ignore directories
	var skip_dirs := [".git", ".godot", "node_modules", ".import", "__pycache__"]

	da.list_dir_begin()
	var file_name := da.get_next()
	while file_name != "":
		var full_path := dir_path + file_name

		if da.current_is_dir():
			if not file_name.begins_with(".") and file_name not in skip_dirs:
				_glob_recursive(full_path + "/", pattern, results)
		else:
			if _match_glob(file_name, pattern):
				results.append(full_path)

		file_name = da.get_next()
	da.list_dir_end()


func _match_glob(file_name: String, pattern: String) -> bool:
	# Handle **/ prefix for recursive match on filename only
	var name_pattern := pattern
	if pattern.begins_with("**/"):
		name_pattern = pattern.substr(3)

	# Simple glob matching: * matches any chars, ? matches single char
	return _glob_match(file_name, name_pattern)


func _glob_match(text: String, pattern: String) -> bool:
	var ti := 0
	var pi := 0
	var star_idx := -1
	var text_star := -1

	while ti < text.length():
		if pi < pattern.length():
			var pc := pattern[pi]
			if pc == '*':
				star_idx = pi
				text_star = ti
				pi += 1
				continue
			elif pc == '?' or pc == text[ti]:
				ti += 1
				pi += 1
				continue

		if star_idx != -1:
			pi = star_idx + 1
			text_star += 1
			ti = text_star
		else:
			return false

	while pi < pattern.length() and pattern[pi] == '*':
		pi += 1

	return pi == pattern.length()
