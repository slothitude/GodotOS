extends Node
## BridgeClient — TCP client connecting GodotOS to the Python bridge daemon
## Protocol: [4-byte LE length][UTF-8 JSON]
## Auto-reconnects with exponential backoff on disconnect.

var _connected: bool = false
var _host: String = "127.0.0.1"
var _port: int = 47625
var _peer: StreamPeerTCP
var _sequence: int = 0

# Reconnect state
var _reconnect_delay: float = 1.0
var _max_reconnect_delay: float = 30.0
var _reconnect_timer: float = 0.0
var _should_reconnect: bool = true

signal bridge_connected
signal bridge_disconnected
signal bridge_reconnected


func connect_to_bridge() -> void:
	_peer = StreamPeerTCP.new()
	print("[BridgeClient] Connecting to %s:%d..." % [_host, _port])
	var err := _peer.connect_to_host(_host, _port)
	if err != OK:
		print("[BridgeClient] TCP connect failed (%d) — running in offline mode" % err)
		_connected = false
		return

	# Poll until connected or timeout
	var timeout := Time.get_ticks_msec() + 3000
	while _peer.get_status() == StreamPeerTCP.STATUS_CONNECTING:
		_peer.poll()
		if Time.get_ticks_msec() > timeout:
			print("[BridgeClient] Connection timed out — running in offline mode")
			_connected = false
			return
		await get_tree().process_frame

	if _peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		_connected = true
		_reconnect_delay = 1.0
		print("[BridgeClient] Connected to bridge at %s:%d" % [_host, _port])
		bridge_connected.emit()
	else:
		print("[BridgeClient] Failed to connect (status: %d) — offline mode" % _peer.get_status())
		_connected = false


func call_service(service: String, action: String, params: Dictionary = {}) -> Dictionary:
	if not _connected or not _peer:
		return {"error": "Not connected to bridge"}

	_sequence += 1
	var command := {
		"id": "bridge_%05d" % _sequence,
		"service": service,
		"action": action,
		"params": params,
	}

	_send_json(command)
	var response: Variant = await _read_json_response()
	if response == null:
		return {"error": "No response from bridge"}
	if response.has("error"):
		return {"error": response.error}
	return response.get("result", {"ok": true})


func _send_json(data: Dictionary) -> bool:
	var json_bytes := JSON.stringify(data).to_utf8_buffer()
	var header := PackedByteArray()
	header.resize(4)
	header.encode_u32(0, json_bytes.size())
	_peer.put_data(header)
	_peer.put_data(json_bytes)
	return true


func _read_json_response() -> Variant:
	# Read header (4 bytes)
	var header = await _read_exact(4)
	if header == null:
		return null
	var length: int = header.decode_u32(0)
	if length > 10_000_000:
		push_error("[BridgeClient] Oversized response: %d bytes" % length)
		return null

	# Read body
	var body = await _read_exact(length)
	if body == null:
		return null

	var json_str: String = body.get_string_from_utf8()
	var parsed = JSON.parse_string(json_str)
	if parsed == null:
		push_error("[BridgeClient] Invalid JSON response")
		return null
	return parsed


func _read_exact(bytes: int) -> Variant:
	var result := PackedByteArray()
	result.resize(bytes)
	var remaining := bytes
	var offset := 0

	var timeout := Time.get_ticks_msec() + 5000
	while remaining > 0:
		_peer.poll()
		var available: int = _peer.get_available_bytes()
		if available > 0:
			var to_read: int = mini(available, remaining)
			var chunk = _peer.get_data(to_read)
			if chunk[0] != OK:
				return null
			for b in chunk[1]:
				result[offset] = b
				offset += 1
				remaining -= 1
		elif _peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			return null
		if Time.get_ticks_msec() > timeout:
			push_error("[BridgeClient] Read timeout")
			return null
		await get_tree().process_frame

	return result


func is_bridge_connected() -> bool:
	return _connected


func _process(_delta: float) -> void:
	if _peer and _connected:
		_peer.poll()
		if _peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			_connected = false
			print("[BridgeClient] Disconnected from bridge")
			bridge_disconnected.emit()
			_should_reconnect = true
			_reconnect_timer = _reconnect_delay

	# Auto-reconnect with exponential backoff
	if not _connected and _should_reconnect:
		_reconnect_timer -= _delta
		if _reconnect_timer <= 0:
			_attempt_reconnect()


func _attempt_reconnect() -> void:
	# Create a fresh peer — old one may be in a non-NONE state
	_peer = StreamPeerTCP.new()

	var err := _peer.connect_to_host(_host, _port)
	if err != OK:
		_reconnect_delay = minf(_reconnect_delay * 2, _max_reconnect_delay)
		_reconnect_timer = _reconnect_delay
		return

	# Poll briefly (non-blocking check)
	for i in range(10):
		_peer.poll()
		if _peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			_connected = true
			_reconnect_delay = 1.0
			print("[BridgeClient] Reconnected to bridge")
			bridge_reconnected.emit()
			# Notify EventRouter
			if Engine.has_singleton("EventRouter"):
				Engine.get_singleton("EventRouter").emit("bridge.reconnected", {"host": _host, "port": _port})
			return
		elif _peer.get_status() != StreamPeerTCP.STATUS_CONNECTING:
			break

	_reconnect_delay = minf(_reconnect_delay * 2, _max_reconnect_delay)
	_reconnect_timer = _reconnect_delay
