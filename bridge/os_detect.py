#!/usr/bin/env python3
"""
Platform detection for GodotOS Bridge.
Provides OS-specific helpers so services work on both Linux and Windows.
"""

import platform
import os
from pathlib import Path


def get_platform() -> str:
    """Return 'linux', 'windows', or 'mac'."""
    system = platform.system().lower()
    if system == "linux":
        return "linux"
    elif system == "windows":
        return "windows"
    elif system == "darwin":
        return "mac"
    return "unknown"


IS_LINUX = get_platform() == "linux"
IS_WINDOWS = get_platform() == "windows"


def home_dir() -> Path:
    """Cross-platform home directory."""
    return Path.home()


def normalize_path(path: str) -> str:
    """Resolve and normalize a path for the current platform."""
    p = Path(path).expanduser()
    if IS_WINDOWS:
        # Expand ~ and env vars on Windows
        p = Path(os.path.expandvars(str(p)))
    return str(p.resolve())


def has_proc() -> bool:
    """Whether /proc filesystem is available (Linux only)."""
    return IS_LINUX and Path("/proc").exists()


def has_sysfs() -> bool:
    """Whether /sys/class is available (Linux only)."""
    return IS_LINUX and Path("/sys/class").exists()
