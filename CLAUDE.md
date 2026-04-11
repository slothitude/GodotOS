# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

GodotOS is an **AI-native graphical shell** built inside Godot Engine 4.6. It runs as a fullscreen desktop session (Wayland/X11 on Linux, borderless window on Windows), replacing traditional DEs like GNOME/KDE. It is the evolution of the [GodotCode editor plugin](https://github.com/slothitude/godotcode) from an editor dock into a standalone operating environment.

**Core principle:** The OS runs the machine, GodotOS runs the experience, GodotCode runs the decisions. Nothing touches the host OS directly — every action flows through the CommandBus.

## Running the Project

```bash
# Clone with submodule
git clone https://github.com/slothitude/GodotOS.git
cd GodotOS
git submodule update --init
bash setup_submodule.sh   # excludes godotcode's project.godot (required!)

# Start the Python bridge daemon (required before Godot launches)
# Linux:
systemctl --user start godotos-bridge
# Or manually:
python3 bridge/bridge_server.py
# Windows:
python bridge/bridge_server.py

# First run: build import cache
godot --editor --headless --quit

# Launch the shell
# Linux (Wayland):
godot --display-driver wayland --path . --main-pack godotos.pck
# Linux (X11) or Windows:
godot --path .

# Install as a desktop session (Linux only)
bash install/install.sh
```

**Requirements:** Godot 4.6+, Python 3.10+, NVIDIA API key (or other supported provider)

**Why `setup_submodule.sh`?** The godotcode submodule has its own `project.godot`. Godot treats any directory with `project.godot` as a separate project and blocks `preload()` across project boundaries. The script configures git sparse-checkout to exclude it — `preload()` works fine without it.

**Updating GodotCode:** `git submodule update --remote` pulls upstream changes (new tools, bug fixes, slash commands). Re-run `setup_submodule.sh` if the sparse-checkout resets.

## Architecture

```
Godot Engine 4.6 (fullscreen)
  └─ shell.gd (boot scene)
       ├─ EventRouter ── pub/sub event system (string channels)
       ├─ OSAdapter ── cross-platform OS abstraction
       ├─ InputRouter ── unified input routing to focused window
       ├─ VirtualFS ── virtual path → host path translation
       ├─ AppLauncher ── JSON manifest scanning, app lifecycle
       ├─ WindowScheduler ── per-window FPS/priority, visibility throttling
       ├─ CommandBus ── all actions validated, logged, reversible
       ├─ ServiceRegistry ── tool/service catalogue (GCToolRegistry from godotcode)
       ├─ StateEngine ── persistent world model of OS state
       ├─ PermissionManager ── policy gates (from godotcode, unchanged)
       ├─ SnapshotSystem ── state persistence, save/restore
       ├─ Watchdog ── self-healing loop, bridge monitoring
       ├─ WindowManager ── floating windows with minimize/maximize
       ├─ Taskbar ── "Nerve Ribbon" with app pills
       ├─ LauncherOverlay ── app grid (Super+Space)
       └─ NotificationLayer
            │
            ▼
       BridgeClient (GDScript TCP client, localhost:47625, auto-reconnect)
            │
            ▼
       BridgeServer (Python asyncio daemon)
            ├─ FSService (read/write/list/search) — cross-platform
            ├─ ProcessService (spawn/kill/list) — cross-platform
            ├─ SystemService (cpu/mem/disk/sensors) — cross-platform
            └─ NetworkService (fetch/dns/ping)
       Linux: Unix socket + TCP adapter | Windows: TCP only
```

### Bridge Protocol

The Godot↔Python bridge uses length-prefixed JSON over TCP: `[4-byte LE length][JSON bytes]`. Commands follow `{id, service, action, params}`. On Linux, `tcp_adapter.py` proxies between GDScript's `StreamPeerTCP` and the Unix socket. On Windows, the bridge listens directly on TCP.

### CommandBus Flow

All commands pass through `CommandBus.execute()` with this schema:
```json
{
  "target": "filesystem|process|window|ai|system|network|event|vfs|app|input",
  "action": "read_file|create_process|open_window|emit|launch|...",
  "params": {},
  "source": "user|agent|system|watchdog",
  "reversible": true
}
```

Steps: validate structure → permission check → log → dispatch to bridge, internal handler, or registered tool → emit signal.

### Boot Sequence

`shell.gd` `_boot_sequence()` initializes in strict order:
1. GCSettings (ConfigFile backend) + shell mode
2. OSAdapter (platform detection)
3. PermissionManager
4. EventRouter
5. StateEngine
6. GCToolRegistry
7. BridgeClient (awaits connection)
8. CommandBus
9. SnapshotSystem
10. Watchdog
11. InputRouter
12. VirtualFS
13. AppLauncher
14. WindowScheduler
15. GC subsystems (ApiClient, QueryEngine, etc.)
16. Register tools + slash commands
17. Register singletons
18. Initialize taskbar
19. Launch AI Console

No autoloads — everything is bootstrapped dynamically to preserve boot order and error handling.

### App Manifest Format

Apps are discovered via `apps/*/manifest.json`:
```json
{"id":"terminal","name":"Terminal","scene":"res://apps/terminal/terminal.tscn","permissions":["process.spawn"],"default_size":[800,500]}
```

## Directory Layout

- `boot/shell.gd` — the desktop, bootstraps all systems
- `boot/shell.tscn` — main scene with all persistent nodes
- `core/` — GodotOS systems: CommandBus, StateEngine, SnapshotSystem, Watchdog, EventRouter, InputRouter, VirtualFS, AppLauncher, WindowScheduler, OSAdapter
- `core/godotos_settings.gd` — GCSettings override (ConfigFile, shell modes)
- `core/godotos_context.gd` — GCContextManager override (no EditorInterface)
- `bridge/` — `bridge_server.py`, `bridge_client.gd`, `tcp_adapter.py`, `os_detect.py`, `services/`
- `wm/` — floating window manager, taskbar, launcher overlay
- `apps/` — bundled applications (each with manifest.json):
  - `ai_console/` — AI Console (GodotOS override of chat_panel.gd)
  - `editor/` — Godot Editor subprocess launcher
  - `terminal/` — Command runner via bridge
  - `file_explorer/` — Tree+list browser via VFS
  - `task_manager/` — Process list + system stats
  - `settings/` — GodotOS config panel
- `tools/` — AI agent tools: `window_tool.gd`, `app_tool.gd`, `vfs_tool.gd`
- `addons/godotcode/` — **git submodule** — all GodotCode source files
- `setup_submodule.sh` — configures sparse-checkout to exclude godotcode's project.godot

## Code Conventions

- **Language:** GDScript 4 (Godot 4.6), Python 3.10+ for the bridge
- **Class naming:** GodotCode components use `GC` prefix (e.g., `GCBaseTool`, `GCQueryEngine`). GodotOS core components have no prefix (e.g., `CommandBus`, `StateEngine`).
- **Submodule preload pattern:** `const GC := "res://addons/godotcode/addons/godotcode/"` then `const X = preload(GC + "path/file.gd")`. GodotOS overrides use direct `preload("res://core/godotos_*.gd")`.
- **Tools:** All extend `GCBaseTool` with `tool_name`, `description`, `input_schema`, `is_read_only`. Override `execute(input, context) → Dictionary` returning `{success, data}` or `{success: false, error}`.
- **App manifests:** JSON files in `apps/*/manifest.json` with `id`, `name`, `scene`, `permissions`, `default_size`.
- **Signals:** Core systems communicate via Godot signals. CommandBus emits `command_started`, `command_completed`, `command_failed`, `command_rejected`. EventRouter emits `event_emitted`.
- **Async:** GDScript `await` for bridge calls and tool execution. Python bridge uses `asyncio.to_thread` for blocking ops.
- **Singletons:** Set via `Engine.register_singleton()` at boot, accessed via `Engine.get_singleton()` / `Engine.has_singleton()`. Not in `[autoload]`.
- **Cross-platform bridge:** `bridge/os_detect.py` detects OS. Services use platform-specific implementations (`/proc` on Linux, `tasklist`/`wmic` on Windows).

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Ctrl+T` | Open Terminal |
| `Super+Space` | Open App Launcher |
| `Ctrl+G` | Toggle AI Console |
| `Ctrl+S` | Save Snapshot |
| `Ctrl+E` | Launch Godot Editor |
| `Ctrl+B` | Open Google in default browser |

## Shell Modes

| Mode | Behavior |
|------|----------|
| `fullscreen` | Borderless fullscreen (default) |
| `hard` | Fullscreen, suitable for Linux desktop session |
| `soft` | Windowed mode, good for development |

## Relationship to GodotCode

GodotCode is a git submodule at `addons/godotcode/`. GodotOS uses it as a library:
- Core engine (query_engine, api_client, tool_registry) — preloaded directly
- All tools — registered in GCToolRegistry via shell.gd
- UI components — loaded via .tscn ext_resource paths into submodule scripts
- Slash commands — registered and routed through AI console

**GodotOS-specific overrides** (4 files that reference EditorInterface):
- `core/godotos_settings.gd` — ConfigFile backend (original uses EditorSettings)
- `core/godotos_context.gd` — OS context (original uses EditorInterface.get_edited_scene_root())
- `apps/ai_console/ai_console.gd` — chat panel (original has EditorPlugin ref)
- `apps/ai_console/image_display.gd` — FileDialog (original uses EditorFileDialog)

The key difference: GodotCode operates on a Godot project. GodotOS operates on the running OS state through the Bridge.

## Project Status

v1.0.0 — Full desktop environment with terminal, file explorer, task manager, settings, launcher overlay, window management (minimize/maximize/restore), event system, virtual filesystem, app lifecycle, snapshots, watchdog recovery, cross-platform bridge (Linux + Windows), and shell modes.
