# GodotOS

> Linux runs the machine. GodotOS runs the experience. GodotCode runs the decisions.

GodotOS transforms the `godotcode` editor plugin into a **standalone Linux graphical shell** — a fullscreen operating environment built inside Godot Engine 4.6, controlled by an AI agent at its core.

This is not a game. This is not a plugin. This is the desktop.

---

## Architecture

```
Linux Kernel
  ↓
systemd + drivers
  ↓
Wayland / X11
  ↓
Godot Engine 4.6  (fullscreen, --display-driver wayland)
  ↓
GodotOS Shell  (boot/shell.gd)
  ↓
┌─────────────────────────────────────────────────────┐
│  CommandBus  ←→  ServiceRegistry  ←→  StateEngine   │
│       ↓                                    ↓         │
│  Permission                          SnapshotSystem  │
│  Manager                             Watchdog        │
└──────────────────┬──────────────────────────────────┘
                   ↓
           BridgeClient (GDScript)
                   ↓  TCP localhost:47625
           BridgeServer (Python asyncio)
           ├── FSService        (read/write/list/search)
           ├── ProcessService   (spawn/kill/list)
           ├── SystemService    (cpu/mem/disk/sensors)
           └── NetworkService   (fetch/dns/ping)
                   ↓
                Linux OS
```

**Key principle:** Nothing touches Linux directly. Every action — from the UI, from an app, from an AI agent — goes through the `CommandBus`. All actions are validated, permission-checked, logged, and reversible.

---

## What's New vs. godotcode (editor plugin)

| godotcode | GodotOS |
|-----------|---------|
| EditorPlugin dock | Fullscreen OS shell |
| Runs inside Godot editor | IS the graphical session |
| Context = project.godot | Context = running OS state |
| No window management | Full floating window manager |
| Direct bash calls | All calls via CommandBus → bridge |
| No persistence | StateEngine + SnapshotSystem |
| No self-healing | Watchdog daemon |
| One app (chat) | Multiple apps (terminal, files, task mgr) |

All the good stuff is preserved and repurposed:
- `query_engine.gd` → powers `AIConsole`
- `api_client.gd` → unchanged
- All tools (`bash`, `web_search`, `agent`, etc.) → now registered in `ServiceRegistry`
- Permission system → unchanged
- Cost tracker → unchanged

---

## Directory Structure

```
godotos/
├── project.godot           ← boot scene = shell, fullscreen
├── CLAUDE.md               ← OS constitution (injected into AI system prompt)
├── boot/
│   └── shell.gd            ← the desktop; bootstraps all systems in order
├── core/
│   ├── command_bus.gd      ← ALL actions flow through here
│   ├── state_engine.gd     ← persistent world model
│   ├── service_registry.gd ← tool/service catalogue
│   ├── snapshot_system.gd  ← auto-snapshots, rollback
│   ├── watchdog.gd         ← self-healing loop
│   └── permission_manager.gd (from godotcode, unchanged)
├── bridge/
│   ├── bridge_server.py    ← Python asyncio daemon
│   ├── tcp_adapter.py      ← Unix socket → TCP proxy for GDScript
│   ├── bridge_client.gd    ← GDScript TCP client
│   └── services/
│       ├── fs_service.py
│       ├── process_service.py
│       ├── system_service.py
│       └── network_service.py
├── wm/
│   └── window_manager.gd   ← floating window system
├── apps/
│   ├── ai_console/         ← GodotCode chat UI (repurposed from editor dock)
│   ├── terminal/           ← real bash via bridge
│   └── task_manager/       ← live process + service monitor
├── tools/                  ← all tools from godotcode + window_tool.gd
└── install/
    └── install.sh          ← registers as Wayland/X11 session, installs bridge service
```

---

## Boot Sequence

1. Godot launches fullscreen (`--display-driver wayland`)
2. `shell.gd` runs `_boot_sequence()`:
   - PermissionManager
   - StateEngine
   - ServiceRegistry (registers all tools)
   - BridgeClient → connects to Python daemon
   - CommandBus (gets bridge + registry + state)
   - SnapshotSystem
   - Watchdog
3. Shell opens AI Console as the first window
4. AI Console registers as `AIConsole` singleton
5. System is live

---

## Install

```bash
# 1. Clone into your preferred location
git clone https://github.com/slothitude/godotcode godotos
cd godotos

# 2. Run installer (sets up systemd service + display manager session)
bash install/install.sh

# 3. Start the bridge manually (or log out and select GodotOS session)
systemctl --user start godotos-bridge

# 4. Launch
godot --display-driver wayland --path . --main-pack godotos.pck
```

Requirements:
- Godot 4.6+
- Python 3.10+
- Linux (X11 or Wayland)
- Anthropic API key (set in AI Console settings)

---

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Ctrl+T` | Open Terminal |
| `Super+Space` | Open Launcher |
| `Ctrl+G` | Toggle AI Console |
| `Ctrl+S` | Save Snapshot |

---

## The Vision

GodotOS is an **AI-native operating environment**. The AI is not a tool you open. It is the shell. Every window, every process, every file operation passes through a system the AI can observe, query, and control.

> *"Set up a Flask server and monitor its health"* — the AI creates the service, spawns the process, opens a window showing its logs, and sets up a watchdog rule. All through the CommandBus. All reversible.

---

## Status

`v0.4.0` — scaffold complete. Core systems implemented. Apps stubbed.

Next: `.tscn` scene files, Taskbar UI, file explorer app, launcher overlay, theming system.

---

MIT License
