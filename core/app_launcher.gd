extends Node
## AppLauncher — discovers and launches apps from manifests
## Scans apps/*/manifest.json, manages app lifecycle.

var _apps: Dictionary = {}  # app_id -> manifest dict
var _running: Dictionary = {}  # app_id -> window_id


func _ready() -> void:
	_scan_apps()


func _scan_apps() -> void:
	_apps.clear()
	var apps_dir := DirAccess.open("res://apps")
	if not apps_dir:
		print("[AppLauncher] No apps directory found")
		return

	apps_dir.list_dir_begin()
	var dir_name := apps_dir.get_next()
	while dir_name != "":
		if apps_dir.current_is_dir() and not dir_name.begins_with("."):
			var manifest_path := "res://apps/%s/manifest.json" % dir_name
			if ResourceLoader.exists(manifest_path):
				_load_manifest(manifest_path)
		dir_name = apps_dir.get_next()
	apps_dir.list_dir_end()

	print("[AppLauncher] Discovered %d apps" % _apps.size())


func _load_manifest(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return
	var json_text := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(json_text)
	if not parsed or not parsed is Dictionary:
		return
	var manifest: Dictionary = parsed
	if not manifest.has("id"):
		return

	# Validate required fields
	if not manifest.has("scene") or not manifest.has("name"):
		return

	_apps[manifest.id] = manifest
	print("[AppLauncher] Registered app: %s (%s)" % [manifest.name, manifest.id])


## Launch an app by ID. Returns the window_id.
func launch(app_id: String, extra_params: Dictionary = {}) -> String:
	if not _apps.has(app_id):
		print("[AppLauncher] Unknown app: %s" % app_id)
		return ""

	var manifest: Dictionary = _apps[app_id]
	var scene: String = manifest.scene
	var title: String = manifest.get("name", app_id)
	var default_size: Array = manifest.get("default_size", [600, 500])

	var params := {
		"title": title,
		"size": Vector2(default_size[0], default_size[1]),
		"app_id": app_id,
	}
	params.merge(extra_params)

	var wm := Engine.get_singleton("WindowManager") if Engine.has_singleton("WindowManager") else null
	if not wm:
		return ""

	var win_id = wm.open_app(scene, params)
	if win_id != "":
		_running[app_id] = win_id

		# Emit event
		if Engine.has_singleton("EventRouter"):
			Engine.get_singleton("EventRouter").emit("app.launched", {"app_id": app_id, "window_id": win_id})

	return win_id


## Close an app by ID.
func close(app_id: String) -> void:
	if not _running.has(app_id):
		return

	var win_id: String = _running[app_id]
	var wm := Engine.get_singleton("WindowManager") if Engine.has_singleton("WindowManager") else null
	if wm:
		wm.close_window(win_id)

	_running.erase(app_id)

	if Engine.has_singleton("EventRouter"):
		Engine.get_singleton("EventRouter").emit("app.closed", {"app_id": app_id})


## List all discovered apps.
func list_apps() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for app_id in _apps:
		var m: Dictionary = _apps[app_id]
		result.append({
			"id": app_id,
			"name": m.get("name", ""),
			"scene": m.get("scene", ""),
			"running": _running.has(app_id),
		})
	return result


## Get manifest for a specific app.
func get_app(app_id: String) -> Dictionary:
	return _apps.get(app_id, {})


## Check if an app is currently running.
func is_running(app_id: String) -> bool:
	return _running.has(app_id)


## Get window_id for a running app.
func get_window_id(app_id: String) -> String:
	return _running.get(app_id, "")


## Called when a window is closed to clean up running state.
func on_window_closed(win_id: String) -> void:
	for app_id in _running:
		if _running[app_id] == win_id:
			_running.erase(app_id)
			if Engine.has_singleton("EventRouter"):
				Engine.get_singleton("EventRouter").emit("app.closed", {"app_id": app_id})
			break
