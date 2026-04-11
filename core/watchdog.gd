extends Node
## Watchdog — self-healing loop for GodotOS
## Monitors bridge health, detects failures, triggers recovery.

var command_bus: Node
var bridge_client: Node

# Health tracking
var _bridge_check_interval: float = 5.0
var _health_timer: Timer
var _bridge_fail_count: int = 0
var _max_bridge_fails: int = 3
var _last_healthy_time: float = 0.0

# Recovery state
var _recovering: bool = false
var _recovery_attempts: int = 0
var _max_recovery_attempts: int = 5
var _recovery_base_delay: float = 2.0

# Failure logging
var _failure_log: Array[Dictionary] = []
const MAX_FAILURE_LOG := 50

signal health_status_changed(healthy: bool)
signal recovery_started(reason: String)
signal recovery_completed
signal recovery_failed(reason: String)


func _ready() -> void:
	print("[Watchdog] Initialized — monitoring bridge health")
	_start_health_checks()


func _start_health_checks() -> void:
	_health_timer = Timer.new()
	_health_timer.wait_time = _bridge_check_interval
	_health_timer.autostart = true
	_health_timer.timeout.connect(_check_health)
	add_child(_health_timer)


func _check_health() -> void:
	if _recovering:
		return

	var bridge_ok := false
	if bridge_client and bridge_client.has_method("is_bridge_connected"):
		bridge_ok = bridge_client.is_bridge_connected()

	if bridge_ok:
		_bridge_fail_count = 0
		_last_healthy_time = Time.get_unix_time_from_system()
	else:
		_bridge_fail_count += 1
		_log_failure("bridge_unhealthy", "Bridge fail count: %d" % _bridge_fail_count)

		if _bridge_fail_count >= _max_bridge_fails:
			_trigger_recovery("Bridge unhealthy (%d consecutive failures)" % _bridge_fail_count)


func _trigger_recovery(reason: String) -> void:
	if _recovering:
		return

	_recovering = true
	_recovery_attempts += 1
	recovery_started.emit(reason)
	print("[Watchdog] Recovery triggered: %s (attempt %d)" % [reason, _recovery_attempts])

	if _recovery_attempts > _max_recovery_attempts:
		print("[Watchdog] Max recovery attempts reached — giving up")
		recovery_failed.emit("Max attempts (%d) reached" % _max_recovery_attempts)
		_recovering = false
		return

	# Emit event for other systems to react
	if Engine.has_singleton("EventRouter"):
		Engine.get_singleton("EventRouter").emit("watchdog.recovery", {
			"reason": reason,
			"attempt": _recovery_attempts,
		})

	# Attempt to restore from snapshot
	_attempt_recovery()


func _attempt_recovery() -> void:
	var delay := _recovery_base_delay * pow(2, _recovery_attempts - 1)
	print("[Watchdog] Waiting %.1fs before recovery attempt..." % delay)
	await get_tree().create_timer(delay).timeout

	# Check if bridge is back
	if bridge_client and bridge_client.has_method("is_bridge_connected"):
		if bridge_client.is_bridge_connected():
			print("[Watchdog] Bridge recovered on its own")
			_recovering = false
			_bridge_fail_count = 0
			recovery_completed.emit()
			return

	# Try to trigger bridge reconnect
	if bridge_client and bridge_client.has_method("_attempt_reconnect"):
		print("[Watchdog] Forcing bridge reconnect...")
		# The bridge_client._process already handles reconnection
		# We just wait a bit and check again
		await get_tree().create_timer(3.0).timeout

		if bridge_client.is_bridge_connected():
			print("[Watchdog] Recovery successful — bridge reconnected")
			_recovering = false
			_bridge_fail_count = 0
			_recovery_attempts = 0
			recovery_completed.emit()
			return

	# Try snapshot restore
	if Engine.has_singleton("SnapshotSystem"):
		print("[Watchdog] Attempting snapshot restore...")
		var ss = Engine.get_singleton("SnapshotSystem")
		if ss.has_method("restore_latest"):
			var result = ss.restore_latest()
			if not result.has("error"):
				print("[Watchdog] Snapshot restored successfully")

	_recovering = false
	health_status_changed.emit(false)


func _log_failure(type: String, message: String) -> void:
	var entry := {
		"type": type,
		"message": message,
		"time": Time.get_unix_time_from_system(),
	}
	_failure_log.append(entry)
	if _failure_log.size() > MAX_FAILURE_LOG:
		_failure_log.pop_front()


## Public API

func get_health_status() -> Dictionary:
	var bridge_ok := false
	if bridge_client and bridge_client.has_method("is_bridge_connected"):
		bridge_ok = bridge_client.is_bridge_connected()
	return {
		"bridge_connected": bridge_ok,
		"bridge_fail_count": _bridge_fail_count,
		"recovering": _recovering,
		"recovery_attempts": _recovery_attempts,
		"last_healthy_time": _last_healthy_time,
	}


func get_failure_log() -> Array[Dictionary]:
	return _failure_log.duplicate()


func force_recovery() -> void:
	_recovery_attempts = 0
	_trigger_recovery("Manual recovery triggered")
