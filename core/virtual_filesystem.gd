extends Node
## VirtualFS — virtual path → host path translation
## Maps virtual paths like /home/user/ to real host paths.
## Supports mount points for cross-platform path abstraction.

var _mounts: Dictionary = {}  # virtual_path -> host_path
var _default_home: String = ""


func _ready() -> void:
	_setup_default_mounts()


func _setup_default_mounts() -> void:
	# Detect host home directory
	var home := _detect_home()
	_default_home = home

	# Default mount points
	_mounts["/home"] = home
	_mounts["/home/user"] = home
	_mounts["/tmp"] = _detect_tmp()
	_mounts["/"] = _detect_root()


func _detect_home() -> String:
	# Use OS environment or bridge to detect home
	if OS.has_environment("HOME"):
		return OS.get_environment("HOME")
	elif OS.has_environment("USERPROFILE"):
		return OS.get_environment("USERPROFILE")
	elif OS.has_environment("HOMEPATH"):
		var drive := OS.get_environment("HOMEDRIVE") if OS.has_environment("HOMEDRIVE") else "C:"
		return drive + OS.get_environment("HOMEPATH")
	return "."


func _detect_tmp() -> String:
	if OS.has_environment("TMP"):
		return OS.get_environment("TMP")
	elif OS.has_environment("TEMP"):
		return OS.get_environment("TEMP")
	return "/tmp"


func _detect_root() -> String:
	if OS.get_name() == "Windows":
		return "C:\\"
	return "/"


## Add a mount point: virtual_path → host_path
func mount(virtual_path: String, host_path: String) -> void:
	_mounts[virtual_path] = host_path


## Remove a mount point.
func unmount(virtual_path: String) -> void:
	_mounts.erase(virtual_path)


## Translate a virtual path to a real host path.
func resolve(virtual_path: String) -> String:
	if virtual_path == "" or virtual_path == "/":
		return _detect_root()

	# Check for exact mount match first
	if _mounts.has(virtual_path):
		return _mounts[virtual_path]

	# Find longest matching mount prefix
	var best_mount := ""
	var best_host := ""
	for vp in _mounts:
		if virtual_path.begins_with(vp) and vp.length() > best_mount.length():
			best_mount = vp
			best_host = _mounts[vp]

	if best_mount != "":
		var relative := virtual_path.substr(best_mount.length())
		if relative.begins_with("/"):
			relative = relative.substr(1)
		if relative == "":
			return best_host
		# Use proper path separator
		var sep := "\\" if OS.get_name() == "Windows" else "/"
		return best_host + sep + relative

	# No mount found — return as-is (might be a real path already)
	return virtual_path


## Translate a host path back to a virtual path.
func virtualize(host_path: String) -> String:
	# Find which mount this host path is under
	var best_mount := ""
	var best_virtual := ""
	for vp in _mounts:
		var hp: String = _mounts[vp]
		if host_path.begins_with(hp) and hp.length() > best_mount.length():
			best_mount = hp
			best_virtual = vp

	if best_mount != "":
		var relative := host_path.substr(best_mount.length())
		relative = relative.replace("\\", "/")
		if relative.begins_with("/"):
			relative = relative.substr(1)
		if relative == "":
			return best_virtual
		return best_virtual + "/" + relative

	return host_path


## Get all mount points.
func get_mounts() -> Dictionary:
	return _mounts.duplicate()


## Get the default home directory (virtual path).
func get_home() -> String:
	return "/home/user"
