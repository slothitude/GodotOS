extends VBoxContainer
## Terminal — command runner via bridge process.spawn
## Simple terminal that sends commands to the bridge and displays output.

var _bridge: Node
var _history: PackedStringArray = []
var _history_index: int = -1
var _current_dir: String = ""

# UI refs
var _output: RichTextLabel
var _input: LineEdit
var _status: Label


func _ready() -> void:
	_bridge = Engine.get_singleton("BridgeClient") if Engine.has_singleton("BridgeClient") else null

	# Set initial working directory
	if OS.has_environment("HOME"):
		_current_dir = OS.get_environment("HOME")
	elif OS.has_environment("USERPROFILE"):
		_current_dir = OS.get_environment("USERPROFILE")
	else:
		_current_dir = "."

	_build_ui()
	_print_welcome()
	_input.grab_focus()


func _build_ui() -> void:
	# Output area
	_output = RichTextLabel.new()
	_output.bbcode_enabled = true
	_output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_output.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_output.add_theme_color_override("default_color", Color(0.78, 0.82, 0.92))
	_output.add_theme_font_size_override("normal_font_size", 14)
	_output.scroll_following = true
	# Dark terminal background
	var output_style := StyleBoxFlat.new()
	output_style.bg_color = Color(0.06, 0.06, 0.10)
	output_style.content_margin_left = 8
	output_style.content_margin_right = 8
	output_style.content_margin_top = 6
	output_style.content_margin_bottom = 6
	_output.add_theme_stylebox_override("normal", output_style)
	add_child(_output)

	# Separator
	var sep := HSeparator.new()
	add_child(sep)

	# Input area
	var input_row := HBoxContainer.new()
	add_child(input_row)

	# Prompt label
	var prompt := Label.new()
	prompt.text = " > "
	prompt.add_theme_color_override("font_color", Color(0.4, 0.6, 1.0))
	prompt.add_theme_font_size_override("font_size", 14)
	input_row.add_child(prompt)

	# Command input
	_input = LineEdit.new()
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.placeholder_text = "Enter command..."
	_input.add_theme_font_size_override("font_size", 14)
	var input_style := StyleBoxFlat.new()
	input_style.bg_color = Color(0.08, 0.08, 0.12)
	input_style.content_margin_left = 4
	_input.add_theme_stylebox_override("normal", input_style)
	_input.text_submitted.connect(_on_command_submitted)
	input_row.add_child(_input)


func _print_welcome() -> void:
	_output.append_text("[color=#4488ff]GodotOS Terminal v0.7[/color]\n")
	_output.append_text("[color=#666666]Type 'help' for available commands[/color]\n\n")


func _print_output(text: String, color: String = "#c8cce8") -> void:
	_output.append_text("[color=%s]%s[/color]\n" % [color, _escape_bb(text)])


func _escape_bb(text: String) -> String:
	return text.replace("[", "[lb]").replace("]", "[rb]")


func _on_command_submitted(command: String) -> void:
	_input.clear()
	if command.strip_edges() == "":
		return

	# Show the command
	_output.append_text("[color=#4488ff] > [/color][color=#e0e0e0]%s[/color]\n" % _escape_bb(command))

	# History
	_history.append(command)
	_history_index = _history.size()

	# Handle built-in commands
	if _handle_builtin(command.strip_edges()):
		return

	# Send to bridge
	_execute_command(command.strip_edges())


func _handle_builtin(cmd: String) -> bool:
	if cmd == "help":
		_print_output("Built-in commands:", "#4488ff")
		_print_output("  help     - Show this help")
		_print_output("  clear    - Clear terminal")
		_print_output("  cd DIR   - Change directory")
		_print_output("  pwd      - Print working directory")
		_print_output("  exit     - Close terminal")
		_print_output("\nOther commands are sent to the bridge.", "#666666")
		return true
	elif cmd == "clear":
		_output.clear()
		return true
	elif cmd == "pwd":
		_print_output(_current_dir)
		return true
	elif cmd.begins_with("cd "):
		var dir := cmd.substr(3).strip_edges()
		if dir == "":
			dir = "~"
		if dir == "~":
			if OS.has_environment("HOME"):
				dir = OS.get_environment("HOME")
			elif OS.has_environment("USERPROFILE"):
				dir = OS.get_environment("USERPROFILE")
		elif not dir.begins_with("/") and not dir.begins_with("\\") and not dir.length() > 1 and dir[1] == ":":
			dir = _current_dir + "/" + dir
		_current_dir = dir
		_print_output("cd: %s" % _current_dir, "#666666")
		return true
	elif cmd == "exit":
		var wm := Engine.get_singleton("WindowManager") if Engine.has_singleton("WindowManager") else null
		if wm:
			# Find our window and close it
			var windows = wm.get_all_windows()
			for win_id in windows:
				var entry: Dictionary = windows[win_id]
				var node = entry.get("node")
				if node == self:
					wm.close_window(win_id)
					break
		return true
	return false


func _execute_command(cmd: String) -> void:
	if not _bridge or not _bridge.is_bridge_connected():
		_print_output("Error: Bridge not connected", "#ff4444")
		return

	# Parse command into cmd + args
	var parts := cmd.split(" ", false)
	if parts.is_empty():
		return

	var executable := parts[0]
	var args: PackedStringArray = []
	if parts.size() > 1:
		for i in range(1, parts.size()):
			args.append(parts[i])

	# Spawn via bridge
	var result = await _bridge.call_service("process", "spawn", {
		"cmd": executable,
		"args": args,
		"cwd": _current_dir,
	})

	if result.has("error"):
		_print_output("Error: %s" % result.error, "#ff4444")
		return

	_print_output("[PID %d] %s" % [result.get("pid", 0), cmd], "#666666")


## Handle input routing from InputRouter.
func _handle_input(event: InputEvent) -> bool:
	if event is InputEventKey and event.pressed:
		# History navigation
		if event.keycode == KEY_UP:
			if _history_index > 0:
				_history_index -= 1
				_input.text = _history[_history_index]
				_input.caret_column = _input.text.length()
			return true
		elif event.keycode == KEY_DOWN:
			if _history_index < _history.size() - 1:
				_history_index += 1
				_input.text = _history[_history_index]
			else:
				_history_index = _history.size()
				_input.text = ""
			_input.caret_column = _input.text.length()
			return true
	return false
