extends Node
## Player options, saved to user://settings.cfg.

const PATH := "user://settings.cfg"

var master := 0.8
var sfx := 0.9
var ambience := 0.5
var sens := 1.0
var pixel := 3
var fov := 80.0
var bob := true
var invert_y := false
var fullscreen := false
var difficulty := 1
var show_fps := false


func _ready() -> void:
	_ensure_bus("SFX")
	_ensure_bus("Ambience")
	load_settings()
	apply()


func _ensure_bus(n: String) -> void:
	if AudioServer.get_bus_index(n) == -1:
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, n)
		AudioServer.set_bus_send(i, "Master")


func apply() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(master, 0.0001)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), linear_to_db(maxf(sfx, 0.0001)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Ambience"), linear_to_db(maxf(ambience, 0.0001)))
	if DisplayServer.get_name() != "headless":
		var fs := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		if fs != fullscreen:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)


func save_settings() -> void:
	var cf := ConfigFile.new()
	for k in ["master", "sfx", "ambience", "sens", "pixel", "fov", "bob", "invert_y", "fullscreen", "difficulty", "show_fps"]:
		cf.set_value("options", k, get(k))
	cf.save(PATH)


func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	for k in ["master", "sfx", "ambience", "sens", "pixel", "fov", "bob", "invert_y", "fullscreen", "difficulty", "show_fps"]:
		set(k, cf.get_value("options", k, get(k)))
