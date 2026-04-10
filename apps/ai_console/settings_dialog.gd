extends AcceptDialog
## Settings dialog for GodotOS AI Console

var _settings: GCSettings

@onready var _provider_option: OptionButton = $Content/ProviderSection/ProviderOption
@onready var _api_key_input: LineEdit = $Content/ApiKeySection/ApiKeyInput
@onready var _model_input: LineEdit = $Content/ModelSection/ModelInput
@onready var _base_url_input: LineEdit = $Content/BaseUrlSection/BaseUrlInput
@onready var _permission_option: OptionButton = $Content/PermissionSection/PermissionOption

const PROVIDERS := [
	{"id": "anthropic", "label": "Anthropic"},
	{"id": "openai", "label": "OpenAI"},
	{"id": "openai_compatible", "label": "OpenAI Compatible"},
]

const PERMISSION_MODES := [
	"default",
	"plan",
	"bypass",
]


func _ready() -> void:
	for p in PROVIDERS:
		_provider_option.add_item(p.label)
	for mode in PERMISSION_MODES:
		_permission_option.add_item(mode)
	_load_settings()
	confirmed.connect(_on_confirmed)
	_provider_option.item_selected.connect(_on_provider_changed)


func _on_provider_changed(index: int) -> void:
	var provider_id: String = PROVIDERS[index].id
	var defaults: Dictionary = GCSettings.PROVIDER_DEFAULTS.get(provider_id, {})
	_model_input.placeholder_text = "e.g. %s" % defaults.get("model", "model-name")
	_base_url_input.placeholder_text = defaults.get("base_url", "https://api.example.com")


func _load_settings() -> void:
	if not _settings:
		return

	_api_key_input.text = _settings.get_api_key()
	_model_input.text = _settings.get_model()
	_base_url_input.text = _settings.get_base_url()

	var current_provider := _settings.get_provider()
	for i in PROVIDERS.size():
		if PROVIDERS[i].id == current_provider:
			_provider_option.selected = i
			_on_provider_changed(i)
			break

	var current_perm := _settings.get_permission_mode()
	for i in PERMISSION_MODES.size():
		if PERMISSION_MODES[i] == current_perm:
			_permission_option.selected = i
			break


func _on_confirmed() -> void:
	if not _settings:
		return

	_settings.set_setting(GCSettings.PROVIDER, PROVIDERS[_provider_option.selected].id)
	_settings.set_setting(GCSettings.API_KEY, _api_key_input.text)
	_settings.set_setting(GCSettings.MODEL, _model_input.text)
	_settings.set_setting(GCSettings.BASE_URL, _base_url_input.text)
	_settings.set_setting(GCSettings.PERMISSION_MODE, PERMISSION_MODES[_permission_option.selected])
