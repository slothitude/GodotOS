class_name GCErrorMonitorTool
extends GCBaseTool
## Read Godot editor errors and output log


func _init() -> void:
	super._init(
		"ErrorMonitor",
		"Read Godot editor errors, warnings, and output log. Use 'get_errors' to see recent errors/warnings, 'get_output' for general output.",
		{
			"action": {
				"type": "string",
				"description": "Action to perform: 'get_errors' for errors/warnings, 'get_output' for general output log",
				"enum": ["get_errors", "get_output"]
			},
			"lines": {
				"type": "integer",
				"description": "Number of recent lines to read (default 200, max 500)"
			}
		}
	)
	is_read_only = true


func validate_input(input: Dictionary) -> Dictionary:
	var action: String = input.get("action", "")
	if action == "":
		return {"valid": false, "error": "action is required ('get_errors' or 'get_output')"}
	if action not in ["get_errors", "get_output"]:
		return {"valid": false, "error": "Invalid action: %s. Use 'get_errors' or 'get_output'" % action}
	return {"valid": true}


func execute(input: Dictionary, context: Dictionary) -> Dictionary:
	var action: String = input.get("action", "get_errors")
	var max_lines: int = mini(input.get("lines", 200), 500)

	var log_lines = _read_log_file()
	if log_lines == null:
		return {"success": false, "error": "No editor log file found. The editor may not have generated logs yet."}

	# Take last N lines
	if log_lines.size() > max_lines:
		log_lines = log_lines.slice(log_lines.size() - max_lines)

	if action == "get_errors":
		return _extract_errors(log_lines)
	else:
		return {"success": true, "data": "## Editor Output (last %d lines)\n%s" % [log_lines.size(), "\n".join(log_lines)]}


func _read_log_file() -> Variant:
	# Godot stores logs in user://logs/
	var log_dir := "user://logs"
	var da := DirAccess.open(log_dir)
	if not da:
		return null

	# Find the most recent log file
	var log_files: Array = []
	da.list_dir_begin()
	var fname := da.get_next()
	while fname != "":
		if not da.current_is_dir() and (fname.ends_with(".log") or fname.ends_with(".txt")):
			log_files.append(fname)
		fname = da.get_next()
	da.list_dir_end()

	if log_files.is_empty():
		return null

	# Sort by name (Godot log files include timestamps, so alphabetical = chronological)
	log_files.sort()
	var latest_log: String = log_dir.path_join(log_files[-1])

	var file := FileAccess.open(latest_log, FileAccess.READ)
	if not file:
		return null

	var text := file.get_as_text()
	file.close()
	return text.split("\n")


func _extract_errors(lines: Array) -> Dictionary:
	var errors: Array = []
	var warnings: Array = []

	var error_patterns := ["SCRIPT ERROR", "ERROR:"]
	var warning_patterns := ["WARNING:"]

	for line in lines:
		var stripped: String = str(line).strip_edges()
		if stripped == "":
			continue

		for pattern in error_patterns:
			if pattern in stripped:
				errors.append(stripped)
				break

		if errors.size() > 0 and stripped == errors[-1]:
			continue  # Already added as error

		for pattern in warning_patterns:
			if pattern in stripped:
				warnings.append(stripped)
				break

	var result := "## Error Monitor Report\n"
	result += "Errors: %d | Warnings: %d\n\n" % [errors.size(), warnings.size()]

	if errors.size() > 0:
		result += "### Errors\n"
		for e in errors:
			result += "- %s\n" % e
		result += "\n"

	if warnings.size() > 0:
		result += "### Warnings\n"
		for w in warnings:
			result += "- %s\n" % w

	if errors.is_empty() and warnings.is_empty():
		result += "No errors or warnings found."

	return {"success": true, "data": result}
