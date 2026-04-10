# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

GodotOS is an **AI-native graphical shell** built inside Godot Engine 4.6. It runs as a fullscreen Linux desktop session (Wayland/X11), replacing traditional DEs like GNOME/KDE. It is the evolution of the [GodotCode editor plugin](https://github.com/slothitude/godotcode) from an editor dock into a standalone operating environment.

**Core principle:** Linux runs the machine, GodotOS runs the experience, GodotCode runs the decisions. Nothing touches Linux directly — every action flows through the CommandBus.

## Running the Project

```bash
# Clone with submodule
git clone https://github.com/slothitude/GodotOS.git
cd GodotOS
git submodule update --init
bash setup_submodule.sh   # excludes godotcode's project.godot (required!)

# Start the Python bridge daemon (required before Godot launches)
systemctl --user start godotos-bridge
# Or manually:
python3 bridge/bridge_server.py

# First run: build import cache
godot --editor --headless --quit

# Launch the shell
godot --display-driver wayland --path . --main-pack godotos.pck

# Install as a desktop session
bash install/install.sh
```

**Requirements:** Godot 4.6+, Python 3.10+, Linux (X11 or Wayland), NVIDIA API key

**Why `setup_submodule.sh`?** The godotcode submodule has its own `project.godot`. Godot treats any directory with `project.godot` as a separate project and blocks `preload()` across project boundaries. The script configures git sparse-checkout to exclude it — `preload()` works fine without it.

**Updating GodotCode:** `git submodule update --remote` pulls upstream changes (new tools, bug fixes, slash commands). Re-run `setup_submodule.sh` if the sparse-checkout resets.

## Architecture

```
Godot Engine 4.6 (fullscreen)
  └─ shell.gd (boot scene)
       ├─ CommandBus ── all actions validated, logged, reversible
       ├─ ServiceRegistry ── tool/service catalogue (GCToolRegistry from godotcode)
       ├─ StateEngine ── persistent world model of OS state
       ├─ PermissionManager ── policy gates (from godotcode, unchanged)
       ├─ SnapshotSystem ── auto-snapshots, rollback
       └─ Watchdog ── self-healing loop
            │
            ▼
       BridgeClient (GDScript TCP client, localhost:47625)
            │
            ▼
       BridgeServer (Python asyncio daemon, Unix socket + TCP adapter)
            ├─ FSService (read/write/list/search)
            ├─ ProcessService (spawn/kill/list)
            ├─ SystemService (cpu/mem/disk/sensors)
            └─ NetworkService (fetch/dns/ping)
```

### Bridge Protocol

The Godot↔Python bridge uses length-prefixed JSON over TCP: `[4-byte LE length][JSON bytes]`. Commands follow `{id, service, action, params}`. The `tcp_adapter.py` proxies between GDScript's `StreamPeerTCP` and the Unix socket.

### CommandBus Flow

All commands pass through `CommandBus.execute()` with this schema:
```json
{
  "target": "filesystem|process|window|ai|system|network",
  "action": "read_file|create_process|open_window|...",
  "params": {},
  "source": "user|agent|system|watchdog",
  "reversible": true
}
```

Steps: validate structure → permission check → log → dispatch to bridge or internal handler → emit signal.

### Boot Sequence

`shell.gd` `_boot_sequence()` initializes in strict order:
1. GCSettings (GodotOS override — ConfigFile backend)
2. PermissionManager (from godotcode submodule)
3. StateEngine
4. GCToolRegistry (from godotcode submodule)
5. BridgeClient (awaits connection)
6. CommandBus
7. SnapshotSystem
8. Watchdog
9. GC subsystems (ApiClient, QueryEngine, ConversationHistory, CostTracker, ContextManager)
10. Register tools + slash commands
11. Register singletons (CommandBus, StateEngine, BridgeClient)
12. Initialize taskbar
13. Launch AI Console as first window

No autoloads — everything is bootstrapped dynamically to preserve boot order and error handling.

## Directory Layout

- `boot/shell.gd` — the desktop, bootstraps all systems
- `core/` — GodotOS-specific: CommandBus, StateEngine, SnapshotSystem, Watchdog
- `core/godotos_settings.gd` — GCSettings override (ConfigFile instead of EditorSettings)
- `core/godotos_context.gd` — GCContextManager override (no EditorInterface)
- `bridge/` — `bridge_server.py`, `bridge_client.gd`, `tcp_adapter.py`, `services/`
- `wm/` — floating window manager
- `apps/ai_console/` — AI Console (GodotOS override of chat_panel.gd), image_display.gd (FileDialog instead of EditorFileDialog)
- `apps/editor/` — Godot Editor subprocess launcher
- `tools/` — `window_tool.gd` (GodotOS-specific)
- `addons/godotcode/` — **git submodule** — all GodotCode source files
- `setup_submodule.sh` — configures sparse-checkout to exclude godotcode's project.godot

### GodotCode Submodule Structure

Files are preloaded from `res://addons/godotcode/addons/godotcode/`:

| Path | Contents |
|------|----------|
| `core/` | api_client, query_engine, conversation_history, cost_tracker, message_types, permission_manager, tool_registry |
| `tools/` | base_tool, bash, file_read/write/edit, glob, grep, agent, plan_mode, task, schedule, sleep, error_monitor, web_search, web_fetch, image_gen, image_fetch |
| `commands/` | base_command, commit, compact, doctor, memory, review |
| `ui/` | code_block, message_display, settings_dialog, theme, tool_approval_dialog, image_display |

**Skipped from submodule** (EditorInterface deps): plugin.gd, chat_panel.gd, scene_tree_tool, node_property_tool, screenshot_tool, plugin_writer_tool, tests/

## Code Conventions

- **Language:** GDScript 4 (Godot 4.6), Python 3.10+ for the bridge
- **Class naming:** GodotCode components use `GC` prefix (e.g., `GCBaseTool`, `GCQueryEngine`). GodotOS core components have no prefix (e.g., `CommandBus`, `StateEngine`).
- **Submodule preload pattern:** `const GC := "res://addons/godotcode/addons/godotcode/"` then `const X = preload(GC + "path/file.gd")`. GodotOS overrides use direct `preload("res://core/godotos_*.gd")`.
- **Tools:** All extend `GCBaseTool` with `tool_name`, `description`, `input_schema`, `is_read_only`. Override `execute(input, context) → Dictionary` returning `{success, data}` or `{success: false, error}`.
- **Slash commands:** Extend `GCBaseCommand` with `command_name`, `description`. Override `execute(args, context) → Dictionary`. Registered in `shell.gd:_register_commands()`.
- **Signals:** Core systems communicate via Godot signals. CommandBus emits `command_started`, `command_completed`, `command_failed`, `command_rejected`.
- **Async:** GDScript `await` is used for bridge calls and tool execution. The `query_engine.gd` agent loop uses `_execute_tool_calls_async()`.
- **Singletons:** Set via `Engine.set_singleton()` at boot, accessed via `Engine.get_singleton()` / `Engine.has_singleton()`. Not in `[autoload]`.

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Ctrl+T` | Open Terminal |
| `Super+Space` | Open Launcher |
| `Ctrl+G` | Toggle AI Console |
| `Ctrl+S` | Save Snapshot |
| `Ctrl+E` | Launch Godot Editor |

## Relationship to GodotCode

GodotCode is a git submodule at `addons/godotcode/`. GodotOS uses it as a library:
- Core engine (query_engine, api_client, tool_registry) — preloaded directly
- All tools — registered in GCToolRegistry via shell.gd
- UI components — loaded via .tscn ext_resource paths into submodule scripts
- Slash commands — registered and routed through AI console

**GodotOS-specific overrides** (3 files that reference EditorInterface):
- `core/godotos_settings.gd` — ConfigFile backend (original uses EditorSettings)
- `core/godotos_context.gd` — OS context (original uses EditorInterface.get_edited_scene_root())
- `apps/ai_console/ai_console.gd` — chat panel (original has EditorPlugin ref)
- `apps/ai_console/image_display.gd` — FileDialog (original uses EditorFileDialog)

The key difference: GodotCode operates on a Godot project. GodotOS operates on the running OS state through the Bridge.

## Project Status

v0.5.0 — GodotCode as submodule, image generation, slash commands, editor app. Next: `.tscn` scene files for remaining apps, file explorer, launcher overlay, theming system.
