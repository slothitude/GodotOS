class_name GCWebSearchTool
extends GCBaseTool
## Web search using SearXNG directly (instant, no heavy crawling)


func _init() -> void:
	super._init(
		"WebSearch",
		"Search the web and return results with titles, snippets, and URLs. Provides up-to-date information from the internet.",
		{
			"query": {
				"type": "string",
				"description": "The search query (at least 2 characters)"
			},
			"limit": {
				"type": "integer",
				"description": "Max number of results to return (default 5, max 20)"
			}
		}
	)


func validate_input(input: Dictionary) -> Dictionary:
	if not input.has("query"):
		return {"valid": false, "error": "query is required"}
	if str(input.get("query", "")).length() < 2:
		return {"valid": false, "error": "query must be at least 2 characters"}
	return {"valid": true}


func execute(input: Dictionary, context: Dictionary) -> Dictionary:
	var query: String = str(input.get("query", ""))
	if query == "":
		return {"success": false, "error": "query is required"}

	var limit := int(input.get("limit", 5))
	limit = mini(limit, 20)

	# Get SearXNG URL from settings
	var searx_base: String = "http://localhost:8889"
	var settings = context.get("settings")
	if settings and settings.has_method("get_searxng_url"):
		searx_base = settings.get_searxng_url()

	# Query SearXNG directly — instant results with titles + snippets
	var searx_url: String = "%s/search?q=%s&format=json&limit=%d" % [searx_base, query.uri_encode(), limit]
	print("[WebSearch] Fetching: ", searx_url)
	var result := await _get_json(searx_url)
	print("[WebSearch] Result empty: %s, keys: %s" % [str(result.is_empty()), str(result.keys())])

	if result.is_empty():
		return {"success": false, "error": "Search failed — is SearXNG running at %s?" % searx_base}

	var results = result.get("results", [])
	if results.size() == 0:
		return {"success": true, "data": "No results found for: %s" % query}

	var output: String = "Search results for: %s\n" % query
	var count := 0
	for r in results:
		if count >= limit:
			break
		var title: String = str(r.get("title", ""))
		var url: String = str(r.get("url", ""))
		var snippet: String = str(r.get("content", ""))
		output += "\n%d. %s" % [count + 1, title]
		output += "\n   %s" % url
		if snippet != "":
			output += "\n   %s" % snippet
		count += 1

	return {"success": true, "data": output}


func _debug_log(msg: String) -> void:
	var f := FileAccess.open("user://websearch_debug.log", FileAccess.WRITE_READ)
	if f:
		f.seek_end()
		f.store_line(msg)
		f.close()


func _get_json(url: String) -> Dictionary:
	_debug_log("[WebSearch] Starting request to: " + url)
	var http := HTTPRequest.new()
	var root: Node = (Engine.get_main_loop() as SceneTree).root
	root.add_child(http)
	http.timeout = 15.0

	# Use Dictionary for mutable state — GDScript lambdas don't capture primitives by reference
	var state: Dictionary = {"output": {}, "done": false}

	var err := http.request(url, PackedStringArray(), HTTPClient.METHOD_GET, "")
	_debug_log("[WebSearch] request() returned: %d (%s)" % [err, error_string(err)])
	if err != OK:
		_debug_log("[WebSearch] request failed immediately, aborting")
		if http.is_inside_tree():
			http.queue_free()
		return {}

	http.request_completed.connect(func(_result, _code, _headers, body: PackedByteArray):
		var text := body.get_string_from_utf8()
		_debug_log("[WebSearch] Completed — code=%d, body_len=%d" % [_code, text.length()])
		_debug_log("[WebSearch] Body preview: " + text.left(200))
		var json := JSON.new()
		if json.parse(text) == OK:
			state["output"] = json.data
		else:
			_debug_log("[WebSearch] JSON parse failed: line %d: %s" % [json.get_error_line(), json.get_error_message()])
		state["done"] = true
	)

	var start := Time.get_ticks_msec()
	while not state["done"]:
		if Time.get_ticks_msec() - start > 20000:
			_debug_log("[WebSearch] Timed out after 20s")
			break
		await Engine.get_main_loop().process_frame

	_debug_log("[WebSearch] Done=%s, output_keys=%s" % [str(state["done"]), str(state["output"].keys())])
	if http.is_inside_tree():
		http.queue_free()
	return state["output"]
