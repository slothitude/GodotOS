class_name GCScheduleTools
extends GCBaseTool
## In-session cron-like scheduling (timers that fire prompts)


func _init() -> void:
	super._init(
		"Schedule",
		"Schedule prompts to fire at future times. Jobs live only in this session.",
		{
			"action": {
				"type": "string",
				"description": "Action: create, delete, list",
				"enum": ["create", "delete", "list"]
			},
			"cron": {
				"type": "string",
				"description": "Cron expression (5-field: M H DoM Mon DoW) or 'once' for one-shot"
			},
			"prompt": {
				"type": "string",
				"description": "Prompt to enqueue when the job fires"
			},
			"job_id": {
				"type": "string",
				"description": "Job ID (for delete)"
			},
			"recurring": {
				"type": "boolean",
				"description": "True for recurring, false for one-shot"
			}
		}
	)


var _jobs: Dictionary = {}
var _next_job_id: int = 1
var _timers: Dictionary = {}  # job_id -> SceneTreeTimer
var _callback: Callable  # To trigger prompts in query engine


func validate_input(input: Dictionary) -> Dictionary:
	var action: String = str(input.get("action", ""))
	match action:
		"create":
			if not input.has("cron"):
				return {"valid": false, "error": "cron is required for create"}
			if not input.has("prompt"):
				return {"valid": false, "error": "prompt is required for create"}
		"delete":
			if not input.has("job_id"):
				return {"valid": false, "error": "job_id is required for delete"}
		"list":
			pass
		_:
			return {"valid": false, "error": "Unknown action: %s" % action}
	return {"valid": true}


func check_permissions(input: Dictionary, context: Dictionary) -> Dictionary:
	return {"behavior": "allow"}


func set_prompt_callback(cb: Callable) -> void:
	_callback = cb


func execute(input: Dictionary, context: Dictionary) -> Dictionary:
	var action: String = str(input.get("action", ""))

	match action:
		"create":
			return _create_job(input)
		"delete":
			return _delete_job(input)
		"list":
			return _list_jobs()
		_:
			return {"success": false, "error": "Unknown action: %s" % action}


func _create_job(input: Dictionary) -> Dictionary:
	var id := str(_next_job_id)
	_next_job_id += 1

	var cron_expr: String = str(input.get("cron", ""))
	var prompt_text: String = str(input.get("prompt", ""))
	var recurring: bool = input.get("recurring", true)

	# Parse simple interval from cron for timer-based approach
	var interval_sec := _parse_interval(cron_expr)
	if interval_sec <= 0:
		return {"success": false, "error": "Could not parse cron: %s" % cron_expr}

	_jobs[id] = {
		"id": id,
		"cron": cron_expr,
		"prompt": prompt_text,
		"recurring": recurring,
		"interval_sec": interval_sec,
		"created_at": Time.get_datetime_string_from_system()
	}

	# Start timer
	_start_timer(id, interval_sec, recurring)

	return {"success": true, "data": "Job #%s created (interval: %ds, recurring: %s)" % [id, interval_sec, recurring]}


func _delete_job(input: Dictionary) -> Dictionary:
	var id := str(input.get("job_id", ""))
	if not _jobs.has(id):
		return {"success": false, "error": "Job not found: %s" % id}

	# Stop timer
	if _timers.has(id):
		_timers[id].set_time_left(0)
		_timers.erase(id)

	_jobs.erase(id)
	return {"success": true, "data": "Job #%s deleted" % id}


func _list_jobs() -> Dictionary:
	var lines: Array = []
	for id in _jobs:
		var j: Dictionary = _jobs[id]
		lines.append("#%s [%s] every %ds: %s" % [j.id, "R" if j.recurring else "1x", j.interval_sec, j.prompt.left(50)])
	if lines.is_empty():
		return {"success": true, "data": "No scheduled jobs"}
	return {"success": true, "data": "\n".join(lines)}


func _start_timer(job_id: String, interval_sec: float, recurring: bool) -> void:
	var timer: SceneTreeTimer = Engine.get_main_loop().create_timer(interval_sec)
	timer.timeout.connect(func():
		var job: Dictionary = _jobs.get(job_id, {})
		if job.is_empty():
			return
		if _callback.is_valid():
			_callback.call(job.prompt)
		if recurring:
			_start_timer(job_id, interval_sec, true)
		else:
			_jobs.erase(job_id)
			_timers.erase(job_id)
	)
	_timers[job_id] = timer


func _parse_interval(cron: String) -> float:
	# Simple cron parsing for intervals
	# */N * * * * -> every N minutes
	var parts := cron.split(" ")
	if parts.size() != 5:
		return 60.0  # Default 1 minute

	# Handle */N for minutes
	if parts[0].begins_with("*/"):
		var n := int(parts[0].substr(2))
		if n > 0:
			return n * 60.0

	# Handle */N for hours
	if parts[1].begins_with("*/"):
		var n := int(parts[1].substr(2))
		if n > 0:
			return n * 3600.0

	# Default: every minute
	return 60.0
