class_name GCSettings
extends RefCounted
## Manages settings stored in a ConfigFile (adapted from GodotCode)
## Replaces EditorSettings with user://godotos_settings.cfg

const SETTINGS_PREFIX := "godotcode/"

# Setting keys
const PROVIDER := "provider"
const API_KEY := "api_key"
const MODEL := "model"
const BASE_URL := "base_url"
const MAX_TOKENS := "max_tokens"
const TEMPERATURE := "temperature"
const PERMISSION_MODE := "permission_mode"
const THEME := "theme"
const CONVERSATION_DIR := "conversation_dir"
const WEB_EYES_URL := "web_eyes_url"
const SEARXNG_URL := "searxng_url"

# Provider options
const PROVIDERS := ["anthropic", "openai", "openai_compatible", "nvidia"]

# Per-provider defaults
const PROVIDER_DEFAULTS := {
	"anthropic": {"base_url": "https://api.anthropic.com", "model": "claude-sonnet-4-20250514"},
	"openai": {"base_url": "https://api.openai.com", "model": "gpt-4o"},
	"openai_compatible": {"base_url": "http://localhost:11434", "model": "llama3"},
	"nvidia": {"base_url": "https://integrate.api.nvidia.com", "model": "google/gemma-4-31b-it"},
}

const DEFAULT_PROVIDER := "nvidia"
const DEFAULT_MAX_TOKENS := 16384
const DEFAULT_TEMPERATURE := 1.0
const DEFAULT_PERMISSION_MODE := "default"
const DEFAULT_THEME := "dark"
const DEFAULT_WEB_EYES_URL := "http://localhost:3000"
const DEFAULT_SEARXNG_URL := "http://localhost:8889"

var _config: ConfigFile
var _config_path := "user://godotos_settings.cfg"


func initialize() -> void:
	_config = ConfigFile.new()
	if FileAccess.file_exists(_config_path):
		_config.load(_config_path)
	_ensure_defaults()


func _ensure_defaults() -> void:
	if not _has_setting(PROVIDER):
		set_setting(PROVIDER, DEFAULT_PROVIDER)
	if not _has_setting(API_KEY):
		set_setting(API_KEY, "")

	var provider := get_provider()
	var defaults: Dictionary = PROVIDER_DEFAULTS.get(provider, PROVIDER_DEFAULTS["openai_compatible"])

	if not _has_setting(MODEL):
		set_setting(MODEL, defaults.get("model", ""))
	if not _has_setting(BASE_URL):
		set_setting(BASE_URL, defaults.get("base_url", ""))
	if not _has_setting(MAX_TOKENS):
		set_setting(MAX_TOKENS, DEFAULT_MAX_TOKENS)
	if not _has_setting(TEMPERATURE):
		set_setting(TEMPERATURE, DEFAULT_TEMPERATURE)
	if not _has_setting(PERMISSION_MODE):
		set_setting(PERMISSION_MODE, DEFAULT_PERMISSION_MODE)
	if not _has_setting(THEME):
		set_setting(THEME, DEFAULT_THEME)
	if not _has_setting(CONVERSATION_DIR):
		set_setting(CONVERSATION_DIR, "")
	if not _has_setting(WEB_EYES_URL):
		set_setting(WEB_EYES_URL, DEFAULT_WEB_EYES_URL)
	if not _has_setting(SEARXNG_URL):
		set_setting(SEARXNG_URL, DEFAULT_SEARXNG_URL)


func _has_setting(key: String) -> bool:
	return _config.has_section_key("settings", SETTINGS_PREFIX + key)


func get_setting(key: String, default: Variant = null) -> Variant:
	var full_key := SETTINGS_PREFIX + key
	if _config.has_section_key("settings", full_key):
		return _config.get_value("settings", full_key, default)
	return default


func set_setting(key: String, value: Variant) -> void:
	_config.set_value("settings", SETTINGS_PREFIX + key, value)
	_config.save(_config_path)


func get_provider() -> String:
	return str(get_setting(PROVIDER, DEFAULT_PROVIDER))


func get_api_key() -> String:
	return str(get_setting(API_KEY, ""))


func get_model() -> String:
	var provider := get_provider()
	var defaults: Dictionary = PROVIDER_DEFAULTS.get(provider, PROVIDER_DEFAULTS["openai_compatible"])
	return str(get_setting(MODEL, defaults.get("model", "")))


func get_base_url() -> String:
	var provider := get_provider()
	var defaults: Dictionary = PROVIDER_DEFAULTS.get(provider, PROVIDER_DEFAULTS["openai_compatible"])
	var url := str(get_setting(BASE_URL, defaults.get("base_url", "")))
	if url.right(1) == "/":
		url = url.left(url.length() - 1)
	return url


func get_max_tokens() -> int:
	return int(get_setting(MAX_TOKENS, DEFAULT_MAX_TOKENS))


func get_temperature() -> float:
	return float(get_setting(TEMPERATURE, DEFAULT_TEMPERATURE))


func get_permission_mode() -> String:
	return str(get_setting(PERMISSION_MODE, DEFAULT_PERMISSION_MODE))


func get_theme() -> String:
	return str(get_setting(THEME, DEFAULT_THEME))


func get_conversation_dir() -> String:
	var dir := str(get_setting(CONVERSATION_DIR, ""))
	if dir == "":
		dir = ProjectSettings.globalize_path("user://godotcode_conversations")
	return dir


func get_web_eyes_url() -> String:
	var url := str(get_setting(WEB_EYES_URL, DEFAULT_WEB_EYES_URL))
	if url.right(1) == "/":
		url = url.left(url.length() - 1)
	return url


func get_searxng_url() -> String:
	var url := str(get_setting(SEARXNG_URL, DEFAULT_SEARXNG_URL))
	if url.right(1) == "/":
		url = url.left(url.length() - 1)
	return url
