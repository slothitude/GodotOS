extends Node
## SoundManager — plays Kenney interface sounds throughout GodotOS

const SOUNDS_DIR := "res://assets/sounds/kenney/Audio/"

# Maps logical event names to sound files
const SOUND_MAP := {
	"startup": "res://assets/sounds/startup.ogg",
	"click": "click_002.ogg",
	"open": "confirmation_001.ogg",
	"close": "close_002.ogg",
	"minimize": "drop_002.ogg",
	"maximize": "toggle_002.ogg",
	"restore": "toggle_004.ogg",
	"error": "error_003.ogg",
	"warning": "error_005.ogg",
	"success": "confirmation_002.ogg",
	"notification": "bong_001.ogg",
	"hover": "glass_001.ogg",
	"switch": "switch_001.ogg",
	"launch": "confirmation_003.ogg",
	"type": "click_004.ogg",
}

var _players: Array[AudioStreamPlayer] = []
var _cache: Dictionary = {}  # path -> AudioStream
var muted: bool = false
var volume_db: float = 0.0


func _ready() -> void:
	# Pre-allocate a pool of 4 AudioStreamPlayers
	for i in range(4):
		var player := AudioStreamPlayer.new()
		player.bus = "Master"
		add_child(player)
		_players.append(player)

	Engine.register_singleton("SoundManager", self)


func play(sound_name: String) -> void:
	if muted:
		return

	var path: String = SOUND_MAP.get(sound_name, "")
	if path == "":
		return

	# Resolve relative paths against Kenney dir
	if not path.begins_with("res://"):
		path = SOUNDS_DIR + path

	var stream: AudioStream = _get_stream(path)
	if not stream:
		return

	var player := _get_available_player()
	player.stream = stream
	player.volume_db = volume_db
	player.play()


func play_file(path: String) -> void:
	if muted:
		return
	var stream: AudioStream = _get_stream(path)
	if not stream:
		return
	var player := _get_available_player()
	player.stream = stream
	player.volume_db = volume_db
	player.play()


func _get_stream(path: String) -> AudioStream:
	if _cache.has(path):
		return _cache[path]
	if not ResourceLoader.exists(path):
		return null
	var stream: AudioStream = load(path)
	if stream:
		_cache[path] = stream
	return stream


func _get_available_player() -> AudioStreamPlayer:
	for player in _players:
		if not player.playing:
			return player
	# All busy — steal the first one
	return _players[0]
