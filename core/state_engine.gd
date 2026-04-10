extends Node
## StateEngine — persistent world model of OS state
## Records all commands, results, and failures for inspection/rollback

var _commands: Dictionary = {}   # id -> command
var _results: Dictionary = {}    # id -> result
var _failures: Dictionary = {}   # id -> error string
var _state: Dictionary = {}      # arbitrary key-value state store


func record_command(cmd: Dictionary) -> void:
	_commands[cmd.get("id", "")] = cmd.duplicate()


func record_result(id: String, result: Dictionary) -> void:
	_results[id] = result


func record_failure(id: String, error: String) -> void:
	_failures[id] = error


func get_command(id: String) -> Dictionary:
	return _commands.get(id, {})


func get_result(id: String) -> Dictionary:
	return _results.get(id, {})


func get_failure(id: String) -> String:
	return _failures.get(id, "")


## Arbitrary state store
func set_state(key: String, value: Variant) -> void:
	_state[key] = value


func get_state(key: String, default: Variant = null) -> Variant:
	return _state.get(key, default)


func get_full_state() -> Dictionary:
	return {
		"commands": _commands.duplicate(),
		"results": _results.duplicate(),
		"failures": _failures.duplicate(),
		"state": _state.duplicate(),
	}
