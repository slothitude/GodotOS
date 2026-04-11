#!/usr/bin/env python3
"""System service — CPU, memory, disk, sensor info. Cross-platform."""

import asyncio
import os
import platform
import shutil
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

IS_WINDOWS = sys.platform == "win32"


class SystemService:
    """Async system information queries. Works on both Linux and Windows."""

    async def info(self) -> dict:
        """Get CPU, memory, and disk usage."""
        if IS_WINDOWS:
            return await asyncio.to_thread(self._info_windows)
        return await asyncio.to_thread(self._info_linux)

    def _info_windows(self) -> dict:
        """System info on Windows using standard libraries."""
        result = {}

        # Memory via os.sysconf isn't available on Windows, use ctypes
        try:
            import ctypes
            kernel32 = ctypes.windll.kernel32
            import ctypes.wintypes
            mem_status = ctypes.c_ulonglong(0)
            kernel32.GlobalMemoryStatusEx(ctypes.pointer(mem_status))
        except Exception:
            pass

        # Use psutil-style approach with subprocess
        try:
            # CPU usage — just report core count as a baseline
            result["cpu_count"] = os.cpu_count() or 0

            # Memory via WMIC
            mem_result = subprocess.run(
                ["wmic", "OS", "get", "FreePhysicalMemory,TotalVisibleMemorySize", "/value"],
                capture_output=True, text=True, timeout=10,
            )
            total_kb = 0
            free_kb = 0
            for line in mem_result.stdout.strip().splitlines():
                line = line.strip()
                if line.startswith("TotalVisibleMemorySize="):
                    total_kb = int(line.split("=", 1)[1])
                elif line.startswith("FreePhysicalMemory="):
                    free_kb = int(line.split("=", 1)[1])
            if total_kb > 0:
                result["memory_total_mb"] = round(total_kb / 1024)
                result["memory_used_mb"] = round((total_kb - free_kb) / 1024)
                result["memory_used_pct"] = round((total_kb - free_kb) / total_kb * 100, 1)
        except Exception:
            pass

        # Disk usage for system drive
        try:
            disk = shutil.disk_usage("/")
            result["disk_total_gb"] = round(disk.total / 1e9, 1)
            result["disk_used_gb"] = round(disk.used / 1e9, 1)
            result["disk_used_pct"] = round(disk.used / disk.total * 100, 1)
        except Exception:
            pass

        # Uptime (Windows)
        try:
            import ctypes
            kernel32 = ctypes.windll.kernel32
            millis = kernel32.GetTickCount64()
            result["uptime_hours"] = round(millis / 1000 / 3600, 1)
        except Exception:
            pass

        result["platform"] = "windows"
        return result

    def _info_linux(self) -> dict:
        """System info from /proc on Linux."""
        result = {}

        # CPU info from /proc/stat
        try:
            stat = Path("/proc/stat").read_text().splitlines()
            cpu_line = stat[0].split()
            if cpu_line[0] == "cpu":
                total = sum(int(x) for x in cpu_line[1:])
                idle = int(cpu_line[4])
                result["cpu_idle_pct"] = round(idle / total * 100, 1) if total else 0
        except Exception:
            pass

        # Memory from /proc/meminfo
        mem = {}
        try:
            for line in Path("/proc/meminfo").read_text().splitlines():
                parts = line.split(":")
                if len(parts) == 2:
                    key = parts[0].strip()
                    val = parts[1].strip().split()[0]
                    mem[key] = int(val)
            total_kb = mem.get("MemTotal", 0)
            avail_kb = mem.get("MemAvailable", 0)
            result["memory_total_mb"] = round(total_kb / 1024)
            result["memory_used_mb"] = round((total_kb - avail_kb) / 1024)
            result["memory_used_pct"] = round((total_kb - avail_kb) / total_kb * 100, 1) if total_kb else 0
        except Exception:
            pass

        # Disk usage for root
        try:
            st = os.statvfs("/")
            total = st.f_blocks * st.f_frsize
            avail = st.f_bavail * st.f_frsize
            result["disk_total_gb"] = round(total / 1e9, 1)
            result["disk_used_gb"] = round((total - avail) / 1e9, 1)
            result["disk_used_pct"] = round((total - avail) / total * 100, 1) if total else 0
        except Exception:
            pass

        # Uptime
        try:
            uptime_secs = float(Path("/proc/uptime").read_text().split()[0])
            result["uptime_hours"] = round(uptime_secs / 3600, 1)
        except Exception:
            pass

        result["platform"] = "linux"
        return result

    async def sensors(self) -> dict:
        """Read thermal/battery sensors where available."""
        if IS_WINDOWS:
            return await asyncio.to_thread(self._sensors_windows)
        return await asyncio.to_thread(self._sensors_linux)

    def _sensors_windows(self) -> dict:
        """Windows: basic battery info via WMIC."""
        result = {}
        try:
            bat_result = subprocess.run(
                ["wmic", "path", "Win32_Battery", "get", "EstimatedChargeRemaining,BatteryStatus", "/value"],
                capture_output=True, text=True, timeout=5,
            )
            for line in bat_result.stdout.strip().splitlines():
                line = line.strip()
                if line.startswith("EstimatedChargeRemaining="):
                    result["battery"] = {"capacity": line.split("=", 1)[1].strip(), "status": "discharging"}
                    break
        except Exception:
            pass
        return result

    def _sensors_linux(self) -> dict:
        """Linux thermal/battery sensors from /sys."""
        result = {}
        # Try thermal zones
        thermal_base = Path("/sys/class/thermal")
        if thermal_base.exists():
            temps = []
            for tz in sorted(thermal_base.iterdir()):
                if tz.name.startswith("thermal_zone"):
                    try:
                        temp = int((tz / "temp").read_text().strip())
                        temps.append({"zone": tz.name, "temp_c": temp / 1000.0})
                    except Exception:
                        continue
            if temps:
                result["thermal"] = temps

        # Battery
        bat_base = Path("/sys/class/power_supply")
        if bat_base.exists():
            for bat in bat_base.iterdir():
                if bat.name.startswith("BAT"):
                    try:
                        result["battery"] = {
                            "capacity": (bat / "capacity").read_text().strip(),
                            "status": (bat / "status").read_text().strip(),
                        }
                    except Exception:
                        continue

        return result
