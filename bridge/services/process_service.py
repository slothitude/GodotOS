#!/usr/bin/env python3
"""Process service — list, spawn, and kill processes. Cross-platform."""

import asyncio
import os
import signal
import subprocess
import sys
from pathlib import Path
from typing import Any

IS_WINDOWS = sys.platform == "win32"


class ProcessService:
    """Async process management. Works on both Linux and Windows."""

    async def list(self, filter_name: str = "") -> dict:
        """List running processes."""
        if IS_WINDOWS:
            return await self._list_windows(filter_name)
        return await self._list_linux(filter_name)

    def _list_windows(self, filter_name: str) -> dict:
        """List processes using tasklist on Windows."""
        try:
            result = subprocess.run(
                ["tasklist", "/fo", "csv", "/nh"],
                capture_output=True, text=True, timeout=10,
            )
            procs = []
            for line in result.stdout.strip().splitlines():
                parts = line.strip().strip('"').split('","')
                if len(parts) >= 2:
                    name = parts[0]
                    pid_str = parts[1]
                    try:
                        pid = int(pid_str)
                    except ValueError:
                        continue
                    if filter_name and filter_name.lower() not in name.lower():
                        continue
                    procs.append({"pid": pid, "cmdline": name, "state": "?"})
            return {"processes": procs, "count": len(procs)}
        except Exception as e:
            return {"error": str(e)}

    def _list_linux(self, filter_name: str) -> dict:
        """List processes from /proc on Linux."""
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

    async def kill(self, pid: int, sig: int = None) -> dict:
        """Send a signal to a process (Linux) or terminate (Windows)."""
        try:
            if IS_WINDOWS:
                # On Windows, use taskkill for forceful termination
                subprocess.run(["taskkill", "/pid", str(pid), "/f"], capture_output=True, timeout=5)
                return {"killed": pid}
            else:
                if sig is None:
                    sig = signal.SIGTERM
                os.kill(pid, sig)
                return {"killed": pid, "signal": sig}
        except ProcessLookupError:
            return {"error": f"Process {pid} not found"}
        except PermissionError:
            return {"error": f"Permission denied for process {pid}"}

    async def open(self, path: str) -> dict:
        """Open a file or URL with the OS default application."""
        try:
            if IS_WINDOWS:
                os.startfile(path)
            else:
                await asyncio.create_subprocess_exec("xdg-open", path)
            return {"opened": path}
        except Exception as e:
            return {"error": str(e)}

    async def info(self, pid: int) -> dict:
        """Get info about a specific process."""
        if IS_WINDOWS:
            return await self._info_windows(pid)
        return await self._info_linux(pid)

    def _info_windows(self, pid: int) -> dict:
        """Get process info on Windows via tasklist."""
        try:
            result = subprocess.run(
                ["tasklist", "/fi", f"PID eq {pid}", "/fo", "csv", "/nh"],
                capture_output=True, text=True, timeout=5,
            )
            for line in result.stdout.strip().splitlines():
                parts = line.strip().strip('"').split('","')
                if len(parts) >= 2:
                    return {"pid": pid, "cmdline": parts[0], "state": "?"}
            return {"error": f"Process {pid} not found"}
        except Exception as e:
            return {"error": str(e)}

    def _info_linux(self, pid: int) -> dict:
        """Get process info from /proc on Linux."""
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
