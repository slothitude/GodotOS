#!/usr/bin/env python3
"""Process service — list, spawn, and kill processes."""

import asyncio
import os
import signal
from typing import Any


class ProcessService:
    """Async process management."""

    async def list(self, filter_name: str = "") -> dict:
        """List running processes. Uses /proc on Linux."""
        def _list():
            procs = []
            proc_dir = Path("/proc")
            if not proc_dir.exists():
                return {"processes": [], "count": 0}
            for entry in sorted(proc_dir.iterdir()):
                if not entry.name.isdigit():
                    continue
                try:
                    cmdline = (entry / "cmdline").read_bytes().decode("utf-8", errors="replace")
                    cmdline = cmdline.replace("\x00", " ").strip()
                    if filter_name and filter_name.lower() not in cmdline.lower():
                        continue
                    stat_data = (entry / "stat").read_text().split()
                    procs.append({
                        "pid": int(entry.name),
                        "cmdline": cmdline,
                        "state": stat_data[2] if len(stat_data) > 2 else "?",
                    })
                except (PermissionError, FileNotFoundError, ProcessLookupError):
                    continue
            return {"processes": procs, "count": len(procs)}

        from pathlib import Path
        return await asyncio.to_thread(_list)

    async def spawn(self, cmd: str, args: list = None, cwd: str = "") -> dict:
        """Spawn a process and return its PID."""
        full_args = [cmd] + (args or [])
        proc = await asyncio.create_subprocess_exec(
            *full_args,
            cwd=cwd or None,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        return {"pid": proc.pid, "cmd": cmd, "args": args or []}

    async def kill(self, pid: int, sig: int = signal.SIGTERM) -> dict:
        """Send a signal to a process."""
        try:
            os.kill(pid, sig)
            return {"killed": pid, "signal": sig}
        except ProcessLookupError:
            return {"error": f"Process {pid} not found"}
        except PermissionError:
            return {"error": f"Permission denied for process {pid}"}

    async def info(self, pid: int) -> dict:
        """Get info about a specific process."""
        def _info():
            try:
                proc_path = Path(f"/proc/{pid}")
                if not proc_path.exists():
                    return {"error": f"Process {pid} not found"}
                cmdline = (proc_path / "cmdline").read_bytes().decode("utf-8", errors="replace").replace("\x00", " ").strip()
                stat_data = (proc_path / "stat").read_text().split()
                return {
                    "pid": pid,
                    "cmdline": cmdline,
                    "state": stat_data[2] if len(stat_data) > 2 else "?",
                    "ppid": int(stat_data[3]) if len(stat_data) > 3 else 0,
                }
            except (PermissionError, FileNotFoundError) as e:
                return {"error": str(e)}

        from pathlib import Path
        return await asyncio.to_thread(_info)
