extends Node
## GodotOS Shell — the desktop. This IS the OS.
## Boots fullscreen, initialises all core systems, owns the window manager.

const SHELL_VERSION := "1.0.0"

# Submodule base path — all GodotCode files live here
const GC := "res://addons/godotcode/addons/godotcode/"

# GodotOS overrides (no EditorInterface deps)
const GCSettings = preload("res://core/godotos_settings.gd")
const GCContextManager = preload("res://core/godotos_context.gd")

# GodotCode core — loaded directly from submodule
const GCPermissionManager = preload(GC + "core/permission_manager.gd")
const GCToolRegistry = preload(GC + "core/tool_registry.gd")
const GCCostTracker = preload(GC + "core/cost_tracker.gd")
const GCConversationHistory = preload(GC + "core/conversation_history.gd")
const GCApiClient = preload(GC + "core/api_client.gd")
const GCQueryEngine = preload(GC + "core/query_engine.gd")
const GCMessageTypes = preload(GC + "core/message_types.gd")

# GodotCode tools — loaded from submodule
const GCBaseTool = preload(GC + "tools/base_tool.gd")
const GCFileReadTool = preload(GC + "tools/file_read_tool.gd")
const GCFileWriteTool = preload(GC + "tools/file_write_tool.gd")
const GCFileEditTool = preload(GC + "tools/file_edit_tool.gd")
const GCGlobTool = preload(GC + "tools/glob_tool.gd")
const GCGrepTool = preload(GC + "tools/grep_tool.gd")
const GCBashTool = preload(GC + "tools/bash_tool.gd")
const GCWebSearchTool = preload(GC + "tools/web_search_tool.gd")
const GCWebFetchTool = preload(GC + "tools/web_fetch_tool.gd")
const GCAgentTool = preload(GC + "tools/agent_tool.gd")
const GCPlanModeTool = preload(GC + "tools/plan_mode_tool.gd")
const GCTaskTools = preload(GC + "tools/task_tools.gd")
const GCScheduleTools = preload(GC + "tools/schedule_tools.gd")
const GCSleepTool = preload(GC + "tools/sleep_tool.gd")
const GCErrorMonitorTool = preload(GC + "tools/error_monitor_tool.gd")
const GCImageGenTool = preload(GC + "tools/image_gen_tool.gd")
const GCImageFetchTool = preload(GC + "tools/image_fetch_tool.gd")

# GodotOS-specific tools
const GCWindowTool = preload("res://tools/window_tool.gd")
const GCAppTool = preload("res://tools/app_tool.gd")
const GCVFSTool = preload("res://tools/vfs_tool.gd")

# GodotCode slash commands
const GCBaseCommand = preload(GC + "commands/base_command.gd")
const GCCommitCommand = preload(GC + "commands/commit_command.gd")
const GCCompactCommand = preload(GC + "commands/compact_command.gd")
const GCDoctorCommand = preload(GC + "commands/doctor_command.gd")
const GCMemoryCommand = preload(GC + "commands/memory_command.gd")
const GCReviewCommand = preload(GC + "commands/review_command.gd")

# GodotCode UI (preloaded for AI console)
const GCImageDisplay = preload(GC + "ui/image_display.gd")
const GCMessageDisplay = preload(GC + "ui/message_display.gd")

@onready var window_manager: Node = $WindowManager
@onready var taskbar: Control = $Taskbar
@onready var wallpaper: ColorRect = $Wallpaper
@onready var notification_layer: CanvasLayer = $NotificationLayer
@onready var event_router: Node = $EventRouter
@onready var launcher_overlay: Control = $LauncherOverlay
@onready var startup_sound: AudioStreamPlayer = $StartupSound
@onready var sound_manager: Node = $SoundManager

# Core systems — initialised in order
var command_bus: Node
var service_registry  # GCToolRegistry (RefCounted)
var state_engine: Node
var bridge_client: Node
var watchdog: Node
var snapshot_system: Node
var permission_manager: RefCounted  # GCPermissionManager
var input_router: Node
var virtual_fs: Node
var app_launcher: Node
var window_scheduler: Node
var os_adapter: Node

# GodotCode subsystems
var gc_settings  # GCSettings
var gc_api_client  # GCApiClient
var gc_query_engine  # GCQueryEngine
var gc_conversation_history  # GCConversationHistory
var gc_cost_tracker  # GCCostTracker
var gc_context_manager  # GCContextManager

# Slash commands
var gc_commands: Dictionary = {}  # command_name -> GCBaseCommand

signal system_ready
signal service_failed(service_name: String, error: String)

func _ready() -> void:
	_set_fullscreen()
	_boot_sequence()

func _set_fullscreen() -> void:
	# Apply shell mode (soft/hard/fullscreen) — needs gc_settings initialized first
	# Will be called again after settings are loaded
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	# Set yin-yang window icon
	var icon := Image.load_from_file("res://assets/icon.png")
	if icon:
		DisplayServer.set_icon(icon)


func _apply_shell_mode() -> void:
	# Read shell mode from settings
	if gc_settings and gc_settings.has_method("get_shell_mode"):
		var mode: String = gc_settings.get_shell_mode()
		match mode:
			"fullscreen":
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
				DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
			"hard":
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
				DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
			"soft":
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
				DisplayServer.window_set_size(Vector2i(1280, 720))
				DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
		print("[GodotOS] Shell mode: %s" % mode)

func _boot_sequence() -> void:
	print("[GodotOS %s] Boot sequence starting..." % SHELL_VERSION)

	# 1. GC Settings — first, many things depend on it
	gc_settings = GCSettings.new()
	gc_settings.initialize()
	_load_env_api_key()
	_apply_shell_mode()

	# 2. OS Adapter — platform detection
	os_adapter = preload("res://core/os_adapter.gd").new()
	os_adapter.name = "OSAdapter"
	add_child(os_adapter)
	Engine.register_singleton("OSAdapter", os_adapter)

	# 3. Permission manager
	permission_manager = GCPermissionManager.new()
	permission_manager._settings = gc_settings

	# 4. EventRouter — pub/sub event system
	# (already added as child node in scene tree)
	Engine.register_singleton("EventRouter", event_router)
	print("[GodotOS] EventRouter initialized.")

	# 4. State engine — world model
	state_engine = preload("res://core/state_engine.gd").new()
	state_engine.name = "StateEngine"
	add_child(state_engine)

	# 5. Service registry (GCToolRegistry) — knows all available tools
	service_registry = GCToolRegistry.new()

	# 6. Bridge client — connects to Python daemon
	bridge_client = preload("res://bridge/bridge_client.gd").new()
	bridge_client.name = "BridgeClient"
	add_child(bridge_client)
	await bridge_client.connect_to_bridge()

	# 7. Command bus — all actions route through here
	command_bus = preload("res://core/command_bus.gd").new()
	command_bus.name = "CommandBus"
	command_bus.bridge = bridge_client
	command_bus.registry = service_registry
	command_bus.state = state_engine
	command_bus.permissions = permission_manager
	add_child(command_bus)

	# 8. Snapshot system
	snapshot_system = preload("res://core/snapshot_system.gd").new()
	snapshot_system.name = "SnapshotSystem"
	snapshot_system.state_engine = state_engine
	add_child(snapshot_system)

	# 9. Watchdog
	watchdog = preload("res://core/watchdog.gd").new()
	watchdog.name = "Watchdog"
	watchdog.command_bus = command_bus
	watchdog.bridge_client = bridge_client
	add_child(watchdog)

	# 10. InputRouter — unified input routing
	input_router = preload("res://core/input_router.gd").new()
	input_router.name = "InputRouter"
	add_child(input_router)

	# 11. VirtualFS — virtual path mapping
	virtual_fs = preload("res://core/virtual_filesystem.gd").new()
	virtual_fs.name = "VirtualFS"
	add_child(virtual_fs)

	# 12. AppLauncher — discovers and launches apps
	app_launcher = preload("res://core/app_launcher.gd").new()
	app_launcher.name = "AppLauncher"
	add_child(app_launcher)

	# 13. WindowScheduler — per-window FPS/priority
	window_scheduler = preload("res://core/window_scheduler.gd").new()
	window_scheduler.name = "WindowScheduler"
	add_child(window_scheduler)

	# 14. GC subsystems (modeled on plugin.gd:_enter_tree)
	_init_gc_subsystems()

	# 15. Register tools and commands
	_register_tools()
	_register_commands()

	# Register globals (WindowManager self-registers in _ready)
	Engine.register_singleton("CommandBus", command_bus)
	Engine.register_singleton("StateEngine", state_engine)
	Engine.register_singleton("BridgeClient", bridge_client)
	Engine.register_singleton("InputRouter", input_router)
	Engine.register_singleton("VirtualFS", virtual_fs)
	Engine.register_singleton("AppLauncher", app_launcher)
	Engine.register_singleton("WindowScheduler", window_scheduler)

	# 16. Initialize taskbar
	taskbar.setup(window_manager, command_bus, bridge_client)

	# Connect WindowManager close signal to AppLauncher
	window_manager.window_closed.connect(app_launcher.on_window_closed)

	# Wire UI sounds via SoundManager
	window_manager.window_opened.connect(func(_id, _p): sound_manager.play("open"))
	window_manager.window_closed.connect(func(_id): sound_manager.play("close"))
	window_manager.window_minimized.connect(func(_id): sound_manager.play("minimize"))
	window_manager.window_maximized.connect(func(_id): sound_manager.play("maximize"))
	window_manager.window_restored.connect(func(_id): sound_manager.play("restore"))

	# Emit boot complete event
	event_router.emit("shell.booted", {"version": SHELL_VERSION})

	print("[GodotOS] Boot complete. Shell is live.")
	sound_manager.play("startup")
	system_ready.emit()
	_launch_startup_apps()


func _load_env_api_key() -> void:
	## Read NVIDIA config from .env file and force-apply settings
	var env_path := ProjectSettings.globalize_path("res://.env")
	if not FileAccess.file_exists(env_path):
		return
	var f := FileAccess.open(env_path, FileAccess.READ)
	if not f:
		return
	var api_key := ""
	var model := ""
	var nim_key := ""
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line.begins_with("NVIDIA_API_KEY="):
			api_key = line.substr(len("NVIDIA_API_KEY="))
		elif line.begins_with("NVIDIA_MODEL="):
			model = line.substr(len("NVIDIA_MODEL="))
		elif line.begins_with("NVIDIA_NIM_API_KEY="):
			nim_key = line.substr(len("NVIDIA_NIM_API_KEY="))
	f.close()
	if api_key == "":
		return
	gc_settings.set_setting("api_key", api_key)
	gc_settings.set_setting("provider", "nvidia")
	gc_settings.set_setting("base_url", "https://integrate.api.nvidia.com")
	if model != "":
		gc_settings.set_setting("model", model)
	else:
		gc_settings.set_setting("model", "moonshotai/kimi-k2.5")
	gc_settings.set_setting("temperature", 1.0)
	gc_settings.set_setting("max_tokens", 16384)
	# If a separate NIM key is provided, store it for image gen
	if nim_key != "":
		gc_settings.set_setting("nim_api_key", nim_key)
	print("[GodotOS] Configured NVIDIA provider from .env (model: %s)" % gc_settings.get_model())


func _init_gc_subsystems() -> void:
	gc_cost_tracker = GCCostTracker.new()

	gc_conversation_history = GCConversationHistory.new()
	gc_conversation_history._settings = gc_settings

	gc_context_manager = GCContextManager.new()

	gc_api_client = GCApiClient.new()
	gc_api_client._settings = gc_settings
	add_child(gc_api_client)

	gc_query_engine = GCQueryEngine.new()
	gc_query_engine._api_client = gc_api_client
	gc_query_engine._tool_registry = service_registry
	gc_query_engine._conversation_history = gc_conversation_history
	gc_query_engine._permission_manager = permission_manager
	gc_query_engine._cost_tracker = gc_cost_tracker
	gc_query_engine._context_manager = gc_context_manager
	gc_query_engine._settings = gc_settings

	print("[GodotOS] GC subsystems initialized.")


func _register_tools() -> void:
	var file_read := GCFileReadTool.new()
	var file_write := GCFileWriteTool.new()
	var file_edit := GCFileEditTool.new()
	var glob := GCGlobTool.new()
	var grep := GCGrepTool.new()
	var bash := GCBashTool.new()
	var web_search := GCWebSearchTool.new()
	var web_fetch := GCWebFetchTool.new()
	var agent := GCAgentTool.new()
	var plan_mode := GCPlanModeTool.new()
	var task_tools := GCTaskTools.new()
	var schedule_tools := GCScheduleTools.new()
	var sleep_tool := GCSleepTool.new()
	var error_monitor := GCErrorMonitorTool.new()
	var window_tool := GCWindowTool.new()
	var app_tool := GCAppTool.new()
	var vfs_tool := GCVFSTool.new()
	var image_gen := GCImageGenTool.new()
	var image_fetch := GCImageFetchTool.new()

	service_registry.register(file_read)
	service_registry.register(file_write)
	service_registry.register(file_edit)
	service_registry.register(glob)
	service_registry.register(grep)
	service_registry.register(bash)
	service_registry.register(web_search)
	service_registry.register(web_fetch)
	service_registry.register(agent)
	service_registry.register(plan_mode)
	service_registry.register(task_tools)
	service_registry.register(schedule_tools)
	service_registry.register(sleep_tool)
	service_registry.register(error_monitor)
	service_registry.register(window_tool)
	service_registry.register(app_tool)
	service_registry.register(vfs_tool)
	service_registry.register(image_gen)
	service_registry.register(image_fetch)

	print("[GodotOS] Registered %d tools." % service_registry.get_tool_names().size())


func _register_commands() -> void:
	var cmd_context := {
		"settings": gc_settings,
		"conversation_history": gc_conversation_history,
		"query_engine": gc_query_engine,
		"tool_registry": service_registry,
		"cost_tracker": gc_cost_tracker,
	}

	var commands := [
		GCCommitCommand.new(),
		GCCompactCommand.new(),
		GCDoctorCommand.new(),
		GCMemoryCommand.new(),
		GCReviewCommand.new(),
	]
	for cmd in commands:
		gc_commands[cmd.command_name] = cmd

	print("[GodotOS] Registered %d slash commands." % gc_commands.size())


func _launch_startup_apps() -> void:
	# Launch AI console on first run
	var win_id = window_manager.open_app("res://apps/ai_console/ai_console.tscn", {
		"title": "GodotCode",
		"position": Vector2(100, 80),
		"size": Vector2(700, 600),
	})
	# Wire GC subsystems into the AI Console instance
	var win = window_manager.get_window_by_id(win_id)
	var win_node = win.get("node")
	if win_node and win_node.has_method("setup"):
		win_node.setup(gc_settings, gc_query_engine, gc_conversation_history, gc_cost_tracker, gc_commands)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("open_terminal"):
		if app_launcher:
			if app_launcher.is_running("terminal"):
				# Focus existing terminal
				var win_id = app_launcher.get_window_id("terminal")
				if win_id != "":
					window_manager.focus_window(win_id)
			else:
				app_launcher.launch("terminal")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("open_launcher"):
		if launcher_overlay:
			if launcher_overlay.is_launcher_visible():
				launcher_overlay.hide_launcher()
			else:
				launcher_overlay.show_launcher()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_ai_console"):
		if Engine.has_singleton("AIConsole"):
			var console = Engine.get_singleton("AIConsole")
			if console.visible:
				console.hide()
			else:
				console.show()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("snapshot_save"):
		var result = snapshot_system.save_snapshot()
		if result.has("ok"):
			print("[GodotOS] Snapshot saved: %s" % result.get("name", ""))
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("open_editor"):
		_launch_editor()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("open_browser"):
		OS.shell_open("https://www.google.com")
		get_viewport().set_input_as_handled()


func get_command_bus() -> Node:
	return command_bus

func get_state_engine() -> Node:
	return state_engine


func _launch_editor() -> void:
	var win_id = window_manager.open_app("res://apps/editor/app_editor.tscn", {
		"title": "Godot Editor",
		"position": Vector2(200, 150),
		"size": Vector2(500, 400),
	})
