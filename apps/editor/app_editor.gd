extends VBoxContainer
## Godot Editor wrapper — launches `godot --editor` as a subprocess via the bridge

var _bridge_client: Node
var _status_label: Label
var _launch_btn: Button
var _pid: int = 0


func _ready() -> void:
	_status_label = $StatusLabel
	_launch_btn = $LaunchBtn
	_launch_btn.pressed.connect(_on_launch)
	_bridge_client = Engine.get_singleton("BridgeClient")
	_update_status()


func _on_launch() -> void:
	if _pid != 0:
		_status_label.text = "Editor already running (PID: %d)" % _pid
		return

	if not _bridge_client:
		_status_label.text = "Bridge not connected"
		return

	_status_label.text = "Launching Godot Editor..."

	var result = await _bridge_client.send_command("process", "spawn", {
		"command": "godot",
		"args": ["--editor"],
		"detached": false,
	})
	if result and result.get("success", false):
		_pid = int(result.get("data", {}).get("pid", 0))
		_status_label.text = "Godot Editor launched (PID: %d)" % _pid
		_launch_btn.text = "Running..."
		_launch_btn.disabled = true
		# Poll for process exit
		_monitor_process()
	else:
		var err := str(result.get("error", "Unknown error")) if result else "No response from bridge"
		_status_label.text = "Failed: %s" % err


func _monitor_process() -> void:
	while _pid != 0:
		await get_tree().create_timer(2.0).timeout
		if not _bridge_client:
			break
		var result = await _bridge_client.send_command("process", "list", {})
		if result and result.get("success", false):
			var procs: Array = result.get("data", {}).get("processes", [])
			var found := false
			for p in procs:
				if int(p.get("pid", -1)) == _pid:
					found = true
					break
			if not found:
				_pid = 0
				_status_label.text = "Editor closed"
				_launch_btn.text = "Launch Editor"
				_launch_btn.disabled = false
				return


func _update_status() -> void:
	_status_label.text = "Ready to launch Godot Editor"
