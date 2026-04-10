class_name GCSleepTool
extends GCBaseTool
## Proactive mode wait — delays before continuing


func _init() -> void:
	super._init(
		"Sleep",
		"Wait for a specified number of seconds before continuing. Use sparingly.",
		{
			"seconds": {
				"type": "number",
				"description": "Number of seconds to wait (max 30)"
			}
		}
	)


func validate_input(input: Dictionary) -> Dictionary:
	if not input.has("seconds"):
		return {"valid": false, "error": "seconds is required"}
	var secs: float = float(input.get("seconds", 0))
	if secs <= 0:
		return {"valid": false, "error": "seconds must be positive"}
	if secs > 30:
		return {"valid": false, "error": "seconds must be 30 or less"}
	return {"valid": true}


func check_permissions(input: Dictionary, context: Dictionary) -> Dictionary:
	return {"behavior": "allow"}


func execute(input: Dictionary, context: Dictionary) -> Dictionary:
	var seconds: float = float(input.get("seconds", 1.0))
	seconds = clampf(seconds, 0.1, 30.0)

	var timer: SceneTreeTimer = Engine.get_main_loop().create_timer(seconds)
	await timer.timeout

	return {"success": true, "data": "Waited %.1f seconds" % seconds}
