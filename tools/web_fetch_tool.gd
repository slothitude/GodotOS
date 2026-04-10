class_name GCWebFetchTool
extends GCBaseTool
## Fetch URL content using the web_eyes local API (crawl + extract)


func _init() -> void:
	super._init(
		"WebFetch",
		"Fetch content from a URL and return it as text.",
		{
			"url": {
				"type": "string",
				"description": "The URL to fetch"
			}
		}
	)


func validate_input(input: Dictionary) -> Dictionary:
	if not input.has("url"):
		return {"valid": false, "error": "url is required"}
	return {"valid": true}


func execute(input: Dictionary, context: Dictionary) -> Dictionary:
	var url: String = str(input.get("url", ""))

	if url == "":
		return {"success": false, "error": "url is required"}

	if not url.begins_with("http://") and not url.begins_with("https://"):
		return {"success": false, "error": "url must start with http:// or https://"}

	var settings: GCSettings = context.get("settings", null)
	var base_url: String = "http://localhost:3000"
	if settings:
		base_url = settings.get_web_eyes_url()

	var body := JSON.stringify({"urls": [url]})
	var result := await _post_json(base_url + "/crawl", body)

	if result == null:
		return {"success": false, "error": "Failed to fetch URL — is web_eyes running at %s?" % base_url}

	var content: String = str(result.get("content", ""))
	if content == "":
		return {"success": false, "error": "No content returned from: %s" % url}

	# Truncate if too long
	if content.length() > 50000:
		content = content.left(50000) + "\n... [truncated]"

	return {"success": true, "data": content}


func _post_json(url: String, json_body: String) -> Dictionary:
	var http := HTTPRequest.new()
	var root: Node = (Engine.get_main_loop() as SceneTree).root
	root.add_child(http)

	var state: Dictionary = {"output": {}, "done": false}

	var headers := ["Content-Type: application/json"]
	http.request(url, headers, HTTPClient.METHOD_POST, json_body)
	http.request_completed.connect(func(_result, _code, _headers, body: PackedByteArray):
		var text := body.get_string_from_utf8()
		var json := JSON.new()
		if json.parse(text) == OK:
			state["output"] = json.data
		state["done"] = true
	)

	var start := Time.get_ticks_msec()
	while not state["done"]:
		if Time.get_ticks_msec() - start > 30000:
			break
		await Engine.get_main_loop().process_frame

	if http.is_inside_tree():
		http.queue_free()
	return state["output"]
