extends Node
## OSAdapter — cross-platform OS abstraction layer for GodotOS
## Provides a unified interface for OS operations regardless of platform.

var _platform: String = ""  # "linux", "windows", "mac"


func _ready() -> void:
	_detect_platform()
	print("[OSAdapter] Platform: %s" % _platform)


func _detect_platform() -> void:
	var os_name := OS.get_name()
	match os_name:
		"Linux", "FreeBSD", "NetBSD", "OpenBSD":
			_platform = "linux"
		"Windows":
			_platform = "windows"
		"macOS":
			_platform = "mac"
		_:
			_platform = "unknown"


## Get the current platform identifier.
func get_platform() -> String:
	return _platform


func is_linux() -> bool:
	return _platform == "linux"


func is_windows() -> bool:
	return _platform == "windows"


func is_mac() -> bool:
	return _platform == "mac"


## Get the home directory for the current user.
func get_home_dir() -> String:
	match _platform:
		"windows":
			if OS.has_environment("USERPROFILE"):
				return OS.get_environment("USERPROFILE")
			var drive := OS.get_environment("HOMEDRIVE") if OS.has_environment("HOMEDRIVE") else "C:"
			return drive + OS.get_environment("HOMEPATH") if OS.has_environment("HOMEPATH") else "C:\\"
		_:
			return OS.get_environment("HOME") if OS.has_environment("HOME") else "/"


## Get a suitable temp directory.
func get_temp_dir() -> String:
	match _platform:
		"windows":
			if OS.has_environment("TEMP"):
				return OS.get_environment("TEMP")
			elif OS.has_environment("TMP"):
				return OS.get_environment("TMP")
			return OS.get_environment("SystemRoot") + "\\Temp" if OS.has_environment("SystemRoot") else "C:\\Temp"
		_:
			return "/tmp"


## Get the path separator for the current platform.
func get_path_separator() -> String:
	return "\\" if _platform == "windows" else "/"


## Get the shell executable for the current platform.
func get_shell() -> String:
	match _platform:
		"windows":
			return "cmd.exe"
		_:
			return "/bin/bash"


## Get the shell arguments for running a command.
func get_shell_args(command: String) -> PackedStringArray:
	match _platform:
		"windows":
			return ["/c", command]
		_:
			return ["-c", command]


## Check if this platform supports Wayland.
func supports_wayland() -> bool:
	return _platform == "linux"


## Check if this platform supports X11.
func supports_x11() -> bool:
	return _platform == "linux"


## Get the data directory for GodotOS.
func get_data_dir() -> String:
	var base := OS.get_data_dir()
	return base + get_path_separator() + "godotos"


## Get platform-specific info summary.
func get_platform_info() -> Dictionary:
	return {
		"platform": _platform,
		"os_name": OS.get_name(),
		"home": get_home_dir(),
		"temp": get_temp_dir(),
		"data_dir": get_data_dir(),
		"shell": get_shell(),
		"cpu_count": OS.get_processor_count(),
		"godot_version": Engine.get_version_info().get("string", ""),
	}
