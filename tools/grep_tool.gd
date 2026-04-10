class_name GCGrepTool
extends GCBaseTool
## Content search using RegEx


func _init() -> void:
	super._init(
		"Grep",
		"Search file contents for patterns using regular expressions.",
		{
			"pattern": {
				"type": "string",
				"description": "The regular expression pattern to search for"
			},
			"path": {
				"type": "string",
				"description": "File or directory to search in"
			},
			"glob": {
				"type": "string",
				"description": "Glob pattern to filter files (e.g. *.gd)"
			},
			"output_mode": {
				"type": "string",
				"description": "Output mode: content (shows lines), files_with_matches, count",
				"enum": ["content", "files_with_matches", "count"]
			},
			"-i": {
				"type": "boolean",
				"description": "Case insensitive search"
			},
			"head_limit": {
				"type": "integer",
				"description": "Limit output to first N results"
			}
		}
	)


func validate_input(input: Dictionary) -> Dictionary:
	if not input.has("pattern"):
		return {"valid": false, "error": "pattern is required"}
	return {"valid": true}


func execute(input: Dictionary, context: Dictionary) -> Dictionary:
	var pattern: String = input.get("pattern", "")
	var search_path: String = input.get("path", "")
	var glob_filter: String = input.get("glob", "")
	var output_mode: String = input.get("output_mode", "content")
	var case_insensitive: bool = input.get("-i", false)
	var head_limit: int = input.get("head_limit", 0)

	if pattern == "":
		return {"success": false, "error": "pattern is required"}

	# Default to project root
	if search_path == "":
		search_path = ProjectSettings.globalize_path("res://")
	elif search_path.begins_with("res://"):
		search_path = ProjectSettings.globalize_path(search_path)

	# Compile regex
	var regex := RegEx.new()
	var compile_pattern := pattern
	if case_insensitive:
		# Add inline case-insensitive flag
		compile_pattern = "(?i)" + compile_pattern
	var err := regex.compile(compile_pattern)
	if err != OK:
		return {"success": false, "error": "Invalid regex pattern: %s" % pattern}

	var results: Array = []

	if FileAccess.file_exists(search_path):
		_search_file(search_path, regex, output_mode, head_limit, results)
	elif DirAccess.dir_exists_absolute(search_path):
		_search_directory(search_path, regex, glob_filter, output_mode, head_limit, results)
	else:
		return {"success": false, "error": "Path not found: %s" % search_path}

	if results.is_empty():
		return {"success": true, "data": "No matches found"}

	return {"success": true, "data": "\n".join(results)}


func _search_directory(dir_path: String, regex: RegEx, glob_filter: String, output_mode: String, head_limit: int, results: Array) -> void:
	var da := DirAccess.open(dir_path)
	if not da:
		return

	var skip_dirs := [".git", ".godot", "node_modules", ".import", "__pycache__"]

	da.list_dir_begin()
	var file_name := da.get_next()
	while file_name != "":
		var full_path := dir_path.path_join(file_name)

		if da.current_is_dir():
			if not file_name.begins_with(".") and file_name not in skip_dirs:
				_search_directory(full_path, regex, glob_filter, output_mode, head_limit, results)
		else:
			# Apply glob filter
			if glob_filter != "" and not _match_simple_glob(file_name, glob_filter):
				file_name = da.get_next()
				continue
			_search_file(full_path, regex, output_mode, head_limit, results)

		if head_limit > 0 and results.size() >= head_limit:
			da.list_dir_end()
			return

		file_name = da.get_next()
	da.list_dir_end()


func _search_file(file_path: String, regex: RegEx, output_mode: String, head_limit: int, results: Array) -> void:
	var file := FileAccess.open(file_path, FileAccess.READ)
	if not file:
		return

	var text := file.get_as_text()
	file.close()

	var matches := regex.search_all(text)
	if matches.is_empty():
		return

	match output_mode:
		"files_with_matches":
			results.append(file_path)
		"count":
			results.append("%s: %d" % [file_path, matches.size()])
		"content":
			var lines := text.split("\n")
			var line_num := 0
			for line in lines:
				line_num += 1
				var line_matches := regex.search_all(line)
				if not line_matches.is_empty():
					results.append("%s:%d: %s" % [file_path, line_num, line.strip_edges()])
					if head_limit > 0 and results.size() >= head_limit:
						return


func _match_simple_glob(file_name: String, pattern: String) -> bool:
	var glob_tool := GCGlobTool.new()
	return glob_tool._glob_match(file_name, pattern)
