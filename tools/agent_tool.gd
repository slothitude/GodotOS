class_name GCAgentTool
extends GCBaseTool
## Spawn sub-agents for parallel/delegated tasks


func _init() -> void:
	super._init(
		"Agent",
		"Launch a specialized agent to handle complex sub-tasks autonomously.",
		{
			"prompt": {
				"type": "string",
				"description": "The task for the agent to perform"
			},
			"subagent_type": {
				"type": "string",
				"description": "Type of agent: general-purpose, Explore, Plan, code-reviewer"
			},
			"description": {
				"type": "string",
				"description": "Short description of what the agent will do"
			}
		}
	)


func validate_input(input: Dictionary) -> Dictionary:
	if not input.has("prompt"):
		return {"valid": false, "error": "prompt is required"}
	return {"valid": true}


func check_permissions(input: Dictionary, context: Dictionary) -> Dictionary:
	# Agents are extensions of the main loop — same permission scope
	return {"behavior": "allow"}


func execute(input: Dictionary, context: Dictionary) -> Dictionary:
	var prompt: String = str(input.get("prompt", ""))
	var agent_type: String = str(input.get("subagent_type", "general-purpose"))

	if prompt == "":
		return {"success": false, "error": "prompt is required"}

	# Create a sub-query engine instance for the agent
	var registry: GCToolRegistry = context.get("tool_registry")
	var settings: GCSettings = null
	if context.has("conversation_history"):
		var hist: GCConversationHistory = context.conversation_history
		settings = hist._settings

	var sub_api := GCApiClient.new()
	sub_api._settings = settings

	var sub_history := GCConversationHistory.new()
	sub_history._settings = settings
	sub_history.add_user_message(prompt)

	var sub_engine := GCQueryEngine.new()
	sub_engine._api_client = sub_api
	sub_engine._tool_registry = registry
	sub_engine._conversation_history = sub_history

	# Collect the result — use Dictionary for mutable state in lambdas
	var state: Dictionary = {"text": "", "done": false}

	sub_engine.stream_text_delta.connect(func(text: String):
		state["text"] += text
	)
	sub_engine.query_complete.connect(func(_result):
		state["done"] = true
	)
	sub_engine.query_error.connect(func(error: Dictionary):
		state["text"] += "\n[Agent Error: %s]" % str(error.get("message", "unknown"))
		state["done"] = true
	)

	sub_engine.submit_message(prompt)

	# Wait for completion with timeout
	var start := Time.get_ticks_msec()
	while not state["done"]:
		if Time.get_ticks_msec() - start > 120000:  # 2 min timeout
			state["text"] += "\n[Agent timed out]"
			break
		await Engine.get_main_loop().process_frame

	sub_api.queue_free()

	if state["text"] == "":
		state["text"] = "[Agent completed with no output]"

	return {"success": true, "data": state["text"]}
