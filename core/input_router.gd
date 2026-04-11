extends Node
## InputRouter — unified input routing to the focused window
## Intercepts unhandled input and forwards it to the active window's node.

var _focused_window_id: String = ""
var _blocked_actions: PackedStringArray = []


func _ready() -> void:
	# Connect to WindowManager signals to track focused window
	_connect_window_manager()


func _connect_window_manager() -> void:
	var wm := Engine.get_singleton("WindowManager") if Engine.has_singleton("WindowManager") else null
	if wm:
		wm.window_focused.connect(_on_window_focused)
		wm.window_closed.connect(_on_window_closed)


func _on_window_focused(win_id: String) -> void:
	_focused_window_id = win_id


func _on_window_closed(win_id: String) -> void:
	if _focused_window_id == win_id:
		_focused_window_id = ""


## Route an input event to the focused window's app node.
## Returns true if the event was handled.
func route_input(event: InputEvent) -> bool:
	if _focused_window_id == "":
		return false

	var wm := Engine.get_singleton("WindowManager") if Engine.has_singleton("WindowManager") else null
	if not wm:
		return false

	var entry: Dictionary = wm.get_window_by_id(_focused_window_id)
	var node = entry.get("node")
	if node and is_instance_valid(node) and node.has_method("_handle_input"):
		return node._handle_input(event)
	return false


## Block a specific input action from being routed.
func block_action(action: String) -> void:
	if not action in _blocked_actions:
		_blocked_actions.append(action)


## Unblock a previously blocked input action.
func unblock_action(action: String) -> void:
	_blocked_actions.erase(action)


func get_focused_window_id() -> String:
	return _focused_window_id
