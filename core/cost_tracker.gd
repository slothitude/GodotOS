class_name GCCostTracker
extends RefCounted
## Token usage and cost tracking per session

var _input_tokens: int = 0
var _output_tokens: int = 0
var _cache_creation_tokens: int = 0
var _cache_read_tokens: int = 0
var _request_count: int = 0

# Pricing per million tokens (adjust per model)
var _input_price_per_million: float = 3.0
var _output_price_per_million: float = 15.0
var _cache_creation_price: float = 3.75
var _cache_read_price: float = 0.30


func add_usage(usage: Dictionary) -> void:
	_input_tokens += int(usage.get("input_tokens", 0))
	_output_tokens += int(usage.get("output_tokens", 0))
	_cache_creation_tokens += int(usage.get("cache_creation_input_tokens", 0))
	_cache_read_tokens += int(usage.get("cache_read_input_tokens", 0))
	_request_count += 1


func get_session_cost() -> float:
	var input_cost := (_input_tokens / 1_000_000.0) * _input_price_per_million
	var output_cost := (_output_tokens / 1_000_000.0) * _output_price_per_million
	var cache_create_cost := (_cache_creation_tokens / 1_000_000.0) * _cache_creation_price
	var cache_read_cost := (_cache_read_tokens / 1_000_000.0) * _cache_read_price
	return input_cost + output_cost + cache_create_cost + cache_read_cost


func get_summary() -> String:
	return "Session: %d requests, %d input tokens, %d output tokens, $%.4f" % [
		_request_count, _input_tokens, _output_tokens, get_session_cost()
	]


func reset() -> void:
	_input_tokens = 0
	_output_tokens = 0
	_cache_creation_tokens = 0
	_cache_read_tokens = 0
	_request_count = 0


func get_input_tokens() -> int:
	return _input_tokens


func get_output_tokens() -> int:
	return _output_tokens


func get_request_count() -> int:
	return _request_count
