extends Node
## SnapshotSystem — state persistence and recovery for GodotOS
## Saves/restores full OS state: window positions, open apps, command history.

var state_engine: Node

const SNAPSHOTS_DIR := "user://snapshots/"
const MAX_SNAPSHOTS := 20


func _ready() -> void:
	# Ensure snapshots directory exists
	var dir := DirAccess.open("user://")
	if dir and not dir.dir_exists("snapshots"):
		dir.make_dir("snapshots")


func save_snapshot(name: String = "") -> Dictionary:
	if not state_engine:
		return {"error": "No state engine"}

	var snap_name := name if name != "" else "snap_%d" % Time.get_unix_time_from_system()
	var snap_data := _capture_state()
	snap_data["name"] = snap_name
	snap_data["timestamp"] = Time.get_unix_time_from_system()

	# Save to file
	var path := SNAPSHOTS_DIR + snap_name + ".json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file:
		return {"error": "Cannot write snapshot file: %s" % path}
	file.store_string(JSON.stringify(snap_data, "\t"))
	file.close()

	# Clean up old snapshots
	_cleanup_old_snapshots()

	print("[SnapshotSystem] Saved snapshot: %s" % snap_name)

	# Emit event
	if Engine.has_singleton("EventRouter"):
		Engine.get_singleton("EventRouter").emit("snapshot.saved", {"name": snap_name})

	return {"ok": true, "name": snap_name, "path": path}


func _capture_state() -> Dictionary:
	var state := {}

	# Capture window state
	var wm := Engine.get_singleton("WindowManager") if Engine.has_singleton("WindowManager") else null
	if wm:
		var windows = wm.get_all_windows()
		var win_list := []
		for win_id in windows:
			var entry: Dictionary = windows[win_id]
			var frame: Control = entry.get("frame")
			var win_state := {
				"id": win_id,
				"scene_path": entry.get("scene_path", ""),
				"title": entry.get("title", ""),
				"app_id": entry.get("params", {}).get("app_id", ""),
			}
			if frame and is_instance_valid(frame):
				win_state["position"] = [frame.position.x, frame.position.y]
				win_state["size"] = [frame.size.x, frame.size.y]
				win_state["state"] = entry.get("window_state", "normal")
			win_list.append(win_state)
		state["windows"] = win_list

	# Capture state engine data
	if state_engine and state_engine.has_method("get_full_state"):
		state["engine"] = state_engine.get_full_state()

	# Capture app launcher running state
	var launcher := Engine.get_singleton("AppLauncher") if Engine.has_singleton("AppLauncher") else null
	if launcher:
		state["running_apps"] = {}
		for app in launcher.list_apps():
			if app.get("running", false):
				state["running_apps"][app.id] = launcher.get_window_id(app.id)

	# Metadata
	var shell = Engine.get_singleton("CommandBus").get_parent() if Engine.has_singleton("CommandBus") else null
	state["godotos_version"] = shell.SHELL_VERSION if shell and "SHELL_VERSION" in shell else "unknown"
	state["captured_at"] = Time.get_datetime_string_from_system()

	return state


func restore_snapshot(name: String) -> Dictionary:
	var path := SNAPSHOTS_DIR + name + ".json"
	if not FileAccess.file_exists(path):
		return {"error": "Snapshot not found: %s" % name}

	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return {"error": "Cannot read snapshot: %s" % name}
	var json_text := file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(json_text)
	if not parsed or not parsed is Dictionary:
		return {"error": "Invalid snapshot format"}

	_apply_state(parsed)
	print("[SnapshotSystem] Restored snapshot: %s" % name)

	if Engine.has_singleton("EventRouter"):
		Engine.get_singleton("EventRouter").emit("snapshot.restored", {"name": name})

	return {"ok": true, "name": name}


func restore_latest() -> Dictionary:
	var snapshots := list_snapshots()
	if snapshots.is_empty():
		return {"error": "No snapshots available"}
	var latest: Dictionary = snapshots[-1]
	return restore_snapshot(latest.get("name", ""))


func _apply_state(snap_data: Dictionary) -> void:
	# Close all current windows
	var wm := Engine.get_singleton("WindowManager") if Engine.has_singleton("WindowManager") else null
	if wm:
		var all_windows = wm.get_all_windows()
		for win_id in all_windows:
			wm.close_window(win_id)

	# Restore windows
	var windows: Array = snap_data.get("windows", [])
	for win_data in windows:
		var scene_path: String = win_data.get("scene_path", "")
		if scene_path == "" or not ResourceLoader.exists(scene_path):
			continue

		var params := {
			"title": win_data.get("title", "Restored"),
		}
		var pos = win_data.get("position", [100, 100])
		params["position"] = Vector2(pos[0], pos[1])
		var sz = win_data.get("size", [600, 500])
		params["size"] = Vector2(sz[0], sz[1])
		params["app_id"] = win_data.get("app_id", "")

		var win_id = wm.open_app(scene_path, params)

		# Restore window state (minimized/maximized)
		var win_state: String = win_data.get("state", "normal")
		if win_state == "minimized" and wm.has_method("minimize_window"):
			wm.minimize_window(win_id)
		elif win_state == "maximized" and wm.has_method("maximize_window"):
			wm.maximize_window(win_id)

	# Restore state engine
	if state_engine and snap_data.has("engine"):
		var engine_data: Dictionary = snap_data.engine
		if engine_data.has("state"):
			for key in engine_data.state:
				state_engine.set_state(key, engine_data.state[key])


func list_snapshots() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var dir := DirAccess.open(SNAPSHOTS_DIR)
	if not dir:
		return result

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".json"):
			var snap_name := file_name.substr(0, file_name.length() - 5)
			var path := SNAPSHOTS_DIR + file_name
			var file := FileAccess.open(path, FileAccess.READ)
			if file:
				var parsed = JSON.parse_string(file.get_as_text())
				file.close()
				if parsed and parsed is Dictionary:
					result.append({
						"name": snap_name,
						"timestamp": parsed.get("timestamp", 0),
						"captured_at": parsed.get("captured_at", ""),
						"window_count": parsed.get("windows", []).size(),
					})
		file_name = dir.get_next()
	dir.list_dir_end()

	# Sort by timestamp (oldest first)
	result.sort_custom(func(a, b): return a.timestamp < b.timestamp)
	return result


func has_snapshots() -> bool:
	return not list_snapshots().is_empty()


func delete_snapshot(name: String) -> Dictionary:
	var path := SNAPSHOTS_DIR + name + ".json"
	if not FileAccess.file_exists(path):
		return {"error": "Snapshot not found: %s" % name}
	var dir := DirAccess.open(SNAPSHOTS_DIR)
	if dir:
		dir.remove(name + ".json")
		return {"ok": true}
	return {"error": "Cannot delete snapshot"}


func _cleanup_old_snapshots() -> void:
	var snapshots := list_snapshots()
	while snapshots.size() > MAX_SNAPSHOTS:
		var oldest: Dictionary = snapshots.pop_front()
		delete_snapshot(oldest.get("name", ""))
