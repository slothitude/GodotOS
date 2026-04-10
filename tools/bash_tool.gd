class_name GCBashTool
extends GCBaseTool
## Execute shell commands with timeout and output capture


func _init() -> void:
	super._init(
		"Bash",
		"Executes a bash command and returns its output. Use for system commands and terminal operations.",
		{
			"command": {
				"type": "string",
				"description": "The command to execute"
			},
			"timeout": {
				"type": "integer",
				"description": "Timeout in milliseconds (default 120000, max 600000)"
			},
			"description": {
				"type": "string",
				"description": "Description of what the command does"
			},
			"run_in_background": {
				"type": "boolean",
				"description": "Run command in background"
			}
		}
	)
	is_read_only = false


func validate_input(input: Dictionary) -> Dictionary:
	if not input.has("command"):
		return {"valid": false, "error": "command is required"}
	var cmd: String = input.get("command", "")
	if _is_dangerous(cmd):
		return {"valid": false, "error": "Command contains dangerous pattern and was blocked for safety"}
	return {"valid": true}


func check_permissions(input: Dictionary, context: Dictionary) -> Dictionary:
	var cmd: String = str(input.get("command", ""))
	return {"behavior": "ask", "message": "Execute command: %s" % cmd}


func execute(input: Dictionary, context: Dictionary) -> Dictionary:
	var command: String = input.get("command", "")
	var timeout_msec: int = input.get("timeout", 120000)
	timeout_msec = mini(timeout_msec, 600000)

	if command == "":
		return {"success": false, "error": "command is required"}

	# Determine working directory
	var working_dir: String = context.get("project_path", "")
	if working_dir == "":
		working_dir = ProjectSettings.globalize_path("res://")

	var output: Array = []
	var exit_code := -1

	# Use OS.execute with output pipe
	var args := _parse_command_args(command)

	# For simple commands, use OS.execute
	var temp_out := ""
	var temp_err := ""

	# Use threaded execution for timeout support
	var thread := Thread.new()
	var thread_result: Dictionary = {}

	thread.start(func():
		var o: PackedByteArray = []
		var e: PackedByteArray = []
		exit_code = OS.execute("bash", ["-c", command], o, true)
		thread_result["stdout"] = o.get_string_from_utf8() if o.size() > 0 else ""
		thread_result["stderr"] = ""
		thread_result["exit_code"] = exit_code
	)

	# Wait with timeout
	var start_time := Time.get_ticks_msec()
	while thread.is_alive():
		if Time.get_ticks_msec() - start_time > timeout_msec:
			# Can't kill thread in GDScript, return timeout
			return {"success": false, "error": "Command timed out after %d ms" % timeout_msec}
		OS.delay_msec(50)

	thread.wait_to_finish()

	var stdout: String = thread_result.get("stdout", "")
	exit_code = thread_result.get("exit_code", -1)

	var result_text := stdout
	if exit_code != 0:
		result_text += "\n[Exit code: %d]" % exit_code

	return {"success": exit_code == 0, "data": result_text, "exit_code": exit_code}


func _parse_command_args(command: String) -> PackedStringArray:
	# Simple splitting — for bash commands we pass through bash -c
	return PackedStringArray(["-c", command])


func _is_dangerous(cmd: String) -> bool:
	var dangerous_patterns := [
		"rm -rf /",
		"rm -rf /*",
		"rm -rf ~",
		"rm -rf ~/*",
		"mkfs.",
		"dd if=",
		":(){:|:&};:",
		"> /dev/sda",
		"chmod -R 777 /",
		"wget.*|.*sh",
		"curl.*|.*sh",
	]
	var lower_cmd := cmd.to_lower()
	for pattern in dangerous_patterns:
		if lower_cmd.find(pattern) != -1:
			return true
	return false
