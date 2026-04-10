#!/usr/bin/env python3
"""System service — CPU, memory, disk, sensor info."""

import asyncio
import os
from pathlib import Path
from typing import Any


class SystemService:
    """Async system information queries."""

    async def info(self) -> dict:
        """Get CPU, memory, and disk usage from /proc."""
        def _info():
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

            return result

        return await asyncio.to_thread(_info)

    async def sensors(self) -> dict:
        """Read thermal/battery sensors where available."""
        def _sensors():
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

        return await asyncio.to_thread(_sensors)
