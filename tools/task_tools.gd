class_name GCTaskTools
extends GCBaseTool
## Task management: create, get, list, update, delete tasks


func _init() -> void:
	super._init(
		"TaskManage",
		"Manage a task list for tracking progress on multi-step work.",
		{
			"action": {
				"type": "string",
				"description": "Action to perform: create, get, list, update, delete",
				"enum": ["create", "get", "list", "update", "delete"]
			},
			"subject": {
				"type": "string",
				"description": "Task title (for create/update)"
			},
			"description": {
				"type": "string",
				"description": "Task description"
			},
			"task_id": {
				"type": "string",
				"description": "Task ID (for get/update/delete)"
			},
			"status": {
				"type": "string",
				"description": "Task status: pending, in_progress, completed, deleted",
				"enum": ["pending", "in_progress", "completed", "deleted"]
			}
		}
	)


var _tasks: Dictionary = {}  # id -> task dict
var _next_id: int = 1


func validate_input(input: Dictionary) -> Dictionary:
	var action: String = str(input.get("action", ""))
	match action:
		"create":
			if not input.has("subject"):
				return {"valid": false, "error": "subject is required for create"}
		"get", "update", "delete":
			if not input.has("task_id"):
				return {"valid": false, "error": "task_id is required for %s" % action}
		"list":
			pass
		_:
			return {"valid": false, "error": "Unknown action: %s" % action}
	return {"valid": true}


func check_permissions(input: Dictionary, context: Dictionary) -> Dictionary:
	return {"behavior": "allow"}


func execute(input: Dictionary, context: Dictionary) -> Dictionary:
	var action: String = str(input.get("action", ""))

	match action:
		"create":
			return _create_task(input)
		"get":
			return _get_task(input)
		"list":
			return _list_tasks()
		"update":
			return _update_task(input)
		"delete":
			return _delete_task(input)
		_:
			return {"success": false, "error": "Unknown action: %s" % action}


func _create_task(input: Dictionary) -> Dictionary:
	var id := str(_next_id)
	_next_id += 1
	_tasks[id] = {
		"id": id,
		"subject": str(input.get("subject", "")),
		"description": str(input.get("description", "")),
		"status": "pending",
		"created_at": Time.get_datetime_string_from_system()
	}
	return {"success": true, "data": "Task #%s created: %s" % [id, _tasks[id].subject]}


func _get_task(input: Dictionary) -> Dictionary:
	var id := str(input.get("task_id", ""))
	if not _tasks.has(id):
		return {"success": false, "error": "Task not found: %s" % id}
	return {"success": true, "data": JSON.stringify(_tasks[id], "\t")}


func _list_tasks() -> Dictionary:
	var lines: Array = []
	for id in _tasks:
		var t: Dictionary = _tasks[id]
		if t.status != "deleted":
			lines.append("#%s [%s] %s" % [t.id, t.status, t.subject])
	if lines.is_empty():
		return {"success": true, "data": "No tasks"}
	return {"success": true, "data": "\n".join(lines)}


func _update_task(input: Dictionary) -> Dictionary:
	var id := str(input.get("task_id", ""))
	if not _tasks.has(id):
		return {"success": false, "error": "Task not found: %s" % id}

	if input.has("status"):
		var new_status := str(input.status)
		if new_status == "deleted":
			_tasks[id].status = "deleted"
		else:
			_tasks[id].status = new_status
	if input.has("subject"):
		_tasks[id].subject = str(input.subject)
	if input.has("description"):
		_tasks[id].description = str(input.description)

	return {"success": true, "data": "Task #%s updated: [%s] %s" % [id, _tasks[id].status, _tasks[id].subject]}


func _delete_task(input: Dictionary) -> Dictionary:
	var id := str(input.get("task_id", ""))
	if not _tasks.has(id):
		return {"success": false, "error": "Task not found: %s" % id}
	_tasks.erase(id)
	return {"success": true, "data": "Task #%s deleted" % id}
