class_name SettingsStore
extends RefCounted
## Persistent settings stored to user://settings.cfg via ConfigFile.
## Singleton-style access through static methods. Handles tutorial state,
## and will host future settings (audio, controls, visual toggles).

const SETTINGS_PATH: String = "user://settings.cfg"

static var _config: ConfigFile = null


## Lazily load the config file from disk. Creates a fresh one if none exists.
static func _ensure_loaded() -> void:
	if _config != null:
		return
	_config = ConfigFile.new()
	var err: Error = _config.load(SETTINGS_PATH)
	if err != OK:
		# First launch or corrupted file — start fresh
		_config = ConfigFile.new()


## Save the current config to disk.
static func _save() -> void:
	_ensure_loaded()
	_config.save(SETTINGS_PATH)


## Whether the player has seen the first-run welcome prompt.
static func get_tutorial_seen() -> bool:
	_ensure_loaded()
	return _config.get_value("tutorial", "has_seen_welcome", false)


## Mark the first-run welcome prompt as seen (or unseen for testing).
static func set_tutorial_seen(value: bool) -> void:
	_ensure_loaded()
	_config.set_value("tutorial", "has_seen_welcome", value)
	_save()
