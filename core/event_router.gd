extends Node
## EventRouter — pub/sub event system for GodotOS
## String-based channels with subscribe/unsubscribe/emit pattern.

## channel -> Array of Callable
var _channels: Dictionary = {}
## Wildcard subscribers (receive all events)
var _wildcards: Array[Callable] = []
## Event history for debugging (last 100 events)
var _history: Array[Dictionary] = []
const MAX_HISTORY := 100


signal event_emitted(channel: String, data: Variant)


## Subscribe a callback to a channel. Returns a token for unsubscribing.
func subscribe(channel: String, callback: Callable) -> Dictionary:
	if not _channels.has(channel):
		_channels[channel] = []
	if not _channels[channel].has(callback):
		_channels[channel].append(callback)
	return {"channel": channel, "callback": callback}


## Subscribe to ALL events (wildcard).
func subscribe_all(callback: Callable) -> void:
	if not _wildcards.has(callback):
		_wildcards.append(callback)


## Unsubscribe a callback from a channel.
func unsubscribe(channel: String, callback: Callable) -> void:
	if _channels.has(channel):
		_channels[channel].erase(callback)
		if _channels[channel].is_empty():
			_channels.erase(channel)


## Unsubscribe from all events.
func unsubscribe_all(callback: Callable) -> void:
	_wildcards.erase(callback)
	for channel in _channels:
		_channels[channel].erase(callback)


## Emit an event on a channel. Calls all subscribers.
func emit(channel: String, data: Variant = null) -> void:
	# Record in history
	var entry := {"channel": channel, "data": data, "time": Time.get_unix_time_from_system()}
	_history.append(entry)
	if _history.size() > MAX_HISTORY:
		_history.pop_front()

	# Notify channel subscribers
	if _channels.has(channel):
		for callback in _channels[channel]:
			callback.call(channel, data)

	# Notify wildcard subscribers
	for callback in _wildcards:
		callback.call(channel, data)

	# Emit signal for node-based listeners
	event_emitted.emit(channel, data)


## Get channels that have at least one subscriber.
func get_channels() -> PackedStringArray:
	var result: PackedStringArray = []
	for channel in _channels:
		if not _channels[channel].is_empty():
			result.append(channel)
	return result


## Get subscriber count for a channel.
func get_subscriber_count(channel: String) -> int:
	if not _channels.has(channel):
		return 0
	return _channels[channel].size()


## Get recent event history.
func get_history(limit: int = 20) -> Array[Dictionary]:
	var count := mini(limit, _history.size())
	var start := _history.size() - count
	var result: Array[Dictionary] = []
	for i in range(start, _history.size()):
		result.append(_history[i])
	return result


## Clear all subscriptions and history.
func reset() -> void:
	_channels.clear()
	_wildcards.clear()
	_history.clear()
